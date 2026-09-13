#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmsystem.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <process.h>
#include <vector>
#include "soundtrack.h"
#include "scene_bytecode.h"
#include "file-output.h"

// AFTERLIGHT: no asset files, middleware, browser or runtime installation.
// All graphics and audio use APIs shipped with Windows 11.
template<class T> void Release(T*& p) { if(p) { p->Release(); p=nullptr; } }
static void Check(HRESULT hr,const char* what) {
    if(FAILED(hr)) { char s[256]; snprintf(s,sizeof(s),"%s (0x%08lX)",what,(unsigned long)hr); throw std::runtime_error(s); }
}
static double Clock() {
    LARGE_INTEGER n,f; QueryPerformanceCounter(&n); QueryPerformanceFrequency(&f);
    return double(n.QuadPart)/double(f.QuadPart);
}
static float Smooth(float a,float b,float t) { t=std::clamp((t-a)/(b-a),0.f,1.f); return t*t*(3-2*t); }
static const char* VertexSource=R"(
struct V { float4 p:SV_POSITION; float2 uv:TEXCOORD0; };
V VSMain(uint id:SV_VertexID) { V o; o.uv=float2((id<<1)&2,id&2); o.p=float4(o.uv*float2(2,-2)+float2(-1,1),0,1); return o; }
)";
#include "postprocess.h"

struct Audio {
    std::vector<int16_t> samples;
    HWAVEOUT device=nullptr;
    WAVEHDR header{};
    bool prepared=false,playing=false,paused=false,muted=false;
    double offset=0,started=0,pausedAt=0;
    DWORD origin=0,normalVolume=0xFFFFFFFF;
    bool Open() {
        WAVEFORMATEX f{}; f.wFormatTag=WAVE_FORMAT_PCM; f.nChannels=2;
        f.nSamplesPerSec=Afterlight::SampleRate; f.wBitsPerSample=16;
        f.nBlockAlign=4; f.nAvgBytesPerSec=f.nSamplesPerSec*4;
        bool result=waveOutOpen(&device,WAVE_MAPPER,&f,0,0,CALLBACK_NULL)==MMSYSERR_NOERROR;
        if(result)waveOutGetVolume(device,&normalVolume);
        return result;
    }
    void Stop() {
        if(device) { waveOutReset(device); if(prepared) { waveOutUnprepareHeader(device,&header,sizeof(header)); prepared=false; } }
        playing=false;
    }
    DWORD Position() {
        MMTIME t{}; t.wType=TIME_SAMPLES;
        if(!device || waveOutGetPosition(device,&t,sizeof(t))!=MMSYSERR_NOERROR) return 0;
        if(t.wType==TIME_SAMPLES) return t.u.sample;
        if(t.wType==TIME_BYTES) return t.u.cb/4;
        return DWORD(double(t.u.ms)*Afterlight::SampleRate/1000.);
    }
    void Play(double seconds) {
        Stop(); offset=std::clamp(seconds,0.,Afterlight::Duration-.001);
        paused=false; pausedAt=offset; started=Clock();
        if(device) {
            size_t first=size_t(offset*Afterlight::SampleRate)*2;
            header={}; header.lpData=reinterpret_cast<char*>(samples.data()+first);
            header.dwBufferLength=DWORD((samples.size()-first)*sizeof(int16_t));
            if(waveOutPrepareHeader(device,&header,sizeof(header))==MMSYSERR_NOERROR) {
                prepared=true; origin=Position();
                if(waveOutWrite(device,&header,sizeof(header))!=MMSYSERR_NOERROR) { waveOutUnprepareHeader(device,&header,sizeof(header)); prepared=false; waveOutClose(device); device=nullptr; }
            } else { waveOutClose(device); device=nullptr; }
        }
        playing=true;
    }
    double Time() {
        if(paused) return pausedAt;
        if(!playing) return offset;
        return std::min(Afterlight::Duration,offset+(device?double(DWORD(Position()-origin))/Afterlight::SampleRate:Clock()-started));
    }
    void Pause() {
        if(!playing) return;
        if(paused) { if(device) waveOutRestart(device); started+=Clock()-pauseClock; paused=false; }
        else { pausedAt=Time(); pauseClock=Clock(); if(device) waveOutPause(device); paused=true; }
    }
    void Mute() { muted=!muted; if(device) waveOutSetVolume(device,muted?0:normalVolume); }
    double pauseClock=0;
    ~Audio() { Stop(); if(device) waveOutClose(device); }
};

struct Renderer {
    ID3D11Device* device=nullptr;
    ID3D11DeviceContext* context=nullptr;
    IDXGISwapChain* swap=nullptr;
    ID3D11RenderTargetView *back=nullptr,*sceneTarget=nullptr;
    ID3D11Texture2D *sceneTexture=nullptr,*uiTexture=nullptr;
    ID3D11ShaderResourceView *sceneView=nullptr,*uiView=nullptr;
    ID3D11Texture2D *geometryTexture=nullptr,*fragmentDepthTexture=nullptr;
    ID3D11RenderTargetView* geometryTarget=nullptr;
    ID3D11ShaderResourceView* geometryView=nullptr;
    ID3D11DepthStencilView* fragmentDepth=nullptr;
    ID3D11DepthStencilState* fragmentDepthState=nullptr;
    ID3D11RasterizerState* fragmentRasterizer=nullptr;
    ID3D11VertexShader *vertex=nullptr,*fragmentVertex=nullptr;
    ID3D11PixelShader *sceneShader=nullptr,*compositeShader=nullptr,*bloomShader=nullptr;
    ID3D11PixelShader *nurseryShader=nullptr,*fragmentPixel=nullptr,*resolveShader=nullptr;
    struct BloomLevel {
        ID3D11Texture2D* texture=nullptr;
        ID3D11RenderTargetView* target=nullptr;
        ID3D11ShaderResourceView* view=nullptr;
        UINT width=0,height=0;
        void Reset() { Release(view); Release(target); Release(texture); }
    } bloom[5],nursery,resolved;
    ID3D11Buffer *frameBuffer=nullptr,*compositeBuffer=nullptr;
    ID3D11SamplerState* sampler=nullptr;
    HDC dc=nullptr; HBITMAP bitmap=nullptr; HGDIOBJ oldBitmap=nullptr;
    uint32_t* pixels=nullptr;
    std::vector<uint32_t> uiPixels;
    UINT width=1280,height=720,renderWidth=1280,renderHeight=720;
    int quality=2; bool software=false;
    std::string adapter;
    static const int UIW=1600,UIH=900;
    ID3DBlob* Compile(const char* source,const char* entry,const char* model) {
        ID3DBlob *code=nullptr,*errors=nullptr;
        HRESULT hr=D3DCompile(source,strlen(source),nullptr,nullptr,nullptr,entry,model,D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&code,&errors);
        if(FAILED(hr)) { std::string message=errors?std::string((char*)errors->GetBufferPointer(),errors->GetBufferSize()):"Shader compiler failed"; Release(errors); throw std::runtime_error(message); }
        Release(errors); return code;
    }
    void Init(HWND hwnd,bool warp) {
        DXGI_SWAP_CHAIN_DESC desc{}; desc.BufferDesc.Width=width; desc.BufferDesc.Height=height;
        desc.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count=1;
        desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; desc.BufferCount=2;
        desc.OutputWindow=hwnd; desc.Windowed=TRUE; desc.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;
        D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_0,D3D_FEATURE_LEVEL_10_1,D3D_FEATURE_LEVEL_10_0};
        HRESULT hr=D3D11CreateDeviceAndSwapChain(nullptr,warp?D3D_DRIVER_TYPE_WARP:D3D_DRIVER_TYPE_HARDWARE,nullptr,0,levels,3,D3D11_SDK_VERSION,&desc,&swap,&device,nullptr,&context);
        software=warp;
        if(FAILED(hr)&&!warp) { software=true; hr=D3D11CreateDeviceAndSwapChain(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,levels,3,D3D11_SDK_VERSION,&desc,&swap,&device,nullptr,&context); }
        Check(hr,"Create Direct3D device");
        int preferredQuality=2;
        IDXGIDevice* dxgi=nullptr; IDXGIAdapter* gpu=nullptr; IDXGIFactory* factory=nullptr;
        if(SUCCEEDED(device->QueryInterface(__uuidof(IDXGIDevice),(void**)&dxgi))) {
            if(SUCCEEDED(dxgi->GetAdapter(&gpu))) { DXGI_ADAPTER_DESC info{}; gpu->GetDesc(&info);
                if(info.DedicatedVideoMemory>=size_t(2)*1024*1024*1024) preferredQuality=3;
                char utf8[512]; WideCharToMultiByte(CP_UTF8,0,info.Description,-1,utf8,sizeof(utf8),nullptr,nullptr); adapter=utf8;
                if(SUCCEEDED(gpu->GetParent(__uuidof(IDXGIFactory),(void**)&factory))) factory->MakeWindowAssociation(hwnd,DXGI_MWA_NO_ALT_ENTER);
            }
        }
        Release(factory); Release(gpu); Release(dxgi);
        ID3DBlob* vs=Compile(VertexSource,"VSMain","vs_4_0");
        Check(device->CreateVertexShader(vs->GetBufferPointer(),vs->GetBufferSize(),nullptr,&vertex),"Create vertex shader"); Release(vs);
        Check(device->CreatePixelShader(SceneBytecode,sizeof(SceneBytecode),nullptr,&sceneShader),"Create scene shader");
        Check(device->CreatePixelShader(NurseryBytecode,sizeof(NurseryBytecode),nullptr,&nurseryShader),"Create nursery preparation shader");
        Check(device->CreateVertexShader(FragmentVertexBytecode,sizeof(FragmentVertexBytecode),nullptr,&fragmentVertex),"Create fragment vertex shader");
        Check(device->CreatePixelShader(FragmentPixelBytecode,sizeof(FragmentPixelBytecode),nullptr,&fragmentPixel),"Create fragment pixel shader");
        Check(device->CreatePixelShader(ResolveBytecode,sizeof(ResolveBytecode),nullptr,&resolveShader),"Create contact shading shader");
        D3D11_DEPTH_STENCIL_DESC depthDesc{};
        depthDesc.DepthEnable=TRUE; depthDesc.DepthWriteMask=D3D11_DEPTH_WRITE_MASK_ALL; depthDesc.DepthFunc=D3D11_COMPARISON_LESS;
        Check(device->CreateDepthStencilState(&depthDesc,&fragmentDepthState),"Create fragment depth state");
        D3D11_RASTERIZER_DESC rasterDesc{};
        rasterDesc.FillMode=D3D11_FILL_SOLID; rasterDesc.CullMode=D3D11_CULL_NONE; rasterDesc.DepthClipEnable=TRUE;
        Check(device->CreateRasterizerState(&rasterDesc,&fragmentRasterizer),"Create fragment rasterizer");
        ID3DBlob* ps=Compile(CompositeSource,"PSMain","ps_4_0");
        Check(device->CreatePixelShader(ps->GetBufferPointer(),ps->GetBufferSize(),nullptr,&compositeShader),"Create compositor"); Release(ps);
        ps=Compile(BloomSource,"PSMain","ps_4_0");
        Check(device->CreatePixelShader(ps->GetBufferPointer(),ps->GetBufferSize(),nullptr,&bloomShader),"Create bloom shader"); Release(ps);
        D3D11_BUFFER_DESC bd{}; bd.ByteWidth=16; bd.Usage=D3D11_USAGE_DEFAULT; bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        Check(device->CreateBuffer(&bd,nullptr,&frameBuffer),"Create frame constants");
        Check(device->CreateBuffer(&bd,nullptr,&compositeBuffer),"Create composite constants");
        D3D11_SAMPLER_DESC sd{}; sd.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP; sd.MaxLOD=D3D11_FLOAT32_MAX;
        Check(device->CreateSamplerState(&sd,&sampler),"Create sampler");
        D3D11_TEXTURE2D_DESC td{}; td.Width=UIW; td.Height=UIH; td.MipLevels=td.ArraySize=1;
        td.Format=DXGI_FORMAT_R8G8B8A8_UNORM; td.SampleDesc.Count=1; td.Usage=D3D11_USAGE_DEFAULT; td.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        Check(device->CreateTexture2D(&td,nullptr,&uiTexture),"Create typography surface");
        Check(device->CreateShaderResourceView(uiTexture,nullptr,&uiView),"Create typography view");
        dc=CreateCompatibleDC(nullptr); BITMAPINFO bi{}; bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth=UIW; bi.bmiHeader.biHeight=-UIH; bi.bmiHeader.biPlanes=1; bi.bmiHeader.biBitCount=32; bi.bmiHeader.biCompression=BI_RGB;
        bitmap=CreateDIBSection(dc,&bi,DIB_RGB_COLORS,(void**)&pixels,nullptr,0); if(!bitmap) throw std::runtime_error("Create typography bitmap failed");
        oldBitmap=SelectObject(dc,bitmap); SetBkMode(dc,TRANSPARENT); uiPixels.resize(UIW*UIH);
        Resize(width,height); SetQuality(software?1:preferredQuality); PrepareNursery();
    }
    void PrepareNursery() {
        // Build a 64^3 optical-depth / flow field from mathematics on this GPU.
        // The 8x8 slice atlas keeps the feature-level-10 rendering path intact.
        D3D11_TEXTURE2D_DESC d{}; d.Width=d.Height=512; d.ArraySize=d.MipLevels=1;
        d.Format=DXGI_FORMAT_R16G16B16A16_FLOAT; d.SampleDesc.Count=1;
        d.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        Check(device->CreateTexture2D(&d,nullptr,&nursery.texture),"Create nursery cache");
        Check(device->CreateRenderTargetView(nursery.texture,nullptr,&nursery.target),"Create nursery cache target");
        Check(device->CreateShaderResourceView(nursery.texture,nullptr,&nursery.view),"Create nursery cache view");
        nursery.width=nursery.height=512;
        float constants[]={512,512,0,0}; context->UpdateSubresource(frameBuffer,0,nullptr,constants,0,0);
        context->PSSetConstantBuffers(0,1,&frameBuffer);
        context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        context->VSSetShader(vertex,nullptr,0); context->PSSetShader(nurseryShader,nullptr,0);
        D3D11_VIEWPORT vp{0,0,512,512,0,1}; context->RSSetViewports(1,&vp);
        context->OMSetRenderTargets(1,&nursery.target,nullptr); context->Draw(3,0);
        context->OMSetRenderTargets(0,nullptr,nullptr);
    }
    void Resize(UINT w,UINT h) {
        if(!device||!w||!h) return;
        context->OMSetRenderTargets(0,nullptr,nullptr); Release(back);
        width=w; height=h; Check(swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0),"Resize window");
        ID3D11Texture2D* buffer=nullptr; Check(swap->GetBuffer(0,__uuidof(ID3D11Texture2D),(void**)&buffer),"Get swap buffer");
        Check(device->CreateRenderTargetView(buffer,nullptr,&back),"Create back buffer"); Release(buffer);
    }
    void SetQuality(int q) {
        quality=q; renderHeight=q==1?540:q==2?720:1080; renderWidth=renderHeight*16/9;
        ID3D11ShaderResourceView* none[8]={}; context->PSSetShaderResources(0,8,none);
        context->OMSetRenderTargets(0,nullptr,nullptr);
        Release(sceneView); Release(sceneTarget); Release(sceneTexture);
        Release(geometryView); Release(geometryTarget); Release(geometryTexture);
        Release(fragmentDepth); Release(fragmentDepthTexture);
        D3D11_TEXTURE2D_DESC d{}; d.Width=renderWidth; d.Height=renderHeight; d.ArraySize=d.MipLevels=1;
        d.Format=DXGI_FORMAT_R16G16B16A16_FLOAT; d.SampleDesc.Count=1; d.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        Check(device->CreateTexture2D(&d,nullptr,&sceneTexture),"Create scene target");
        Check(device->CreateRenderTargetView(sceneTexture,nullptr,&sceneTarget),"Create scene target view");
        Check(device->CreateShaderResourceView(sceneTexture,nullptr,&sceneView),"Create scene resource");
        d.Format=DXGI_FORMAT_R32_FLOAT;
        Check(device->CreateTexture2D(&d,nullptr,&geometryTexture),"Create geometry distance surface");
        Check(device->CreateRenderTargetView(geometryTexture,nullptr,&geometryTarget),"Create geometry distance target");
        Check(device->CreateShaderResourceView(geometryTexture,nullptr,&geometryView),"Create geometry distance view");
        d.Format=DXGI_FORMAT_D32_FLOAT; d.BindFlags=D3D11_BIND_DEPTH_STENCIL;
        Check(device->CreateTexture2D(&d,nullptr,&fragmentDepthTexture),"Create fragment depth surface");
        Check(device->CreateDepthStencilView(fragmentDepthTexture,nullptr,&fragmentDepth),"Create fragment depth view");
        d.Format=DXGI_FORMAT_R16G16B16A16_FLOAT; d.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
        resolved.Reset();
        Check(device->CreateTexture2D(&d,nullptr,&resolved.texture),"Create resolved scene");
        Check(device->CreateRenderTargetView(resolved.texture,nullptr,&resolved.target),"Create resolved scene target");
        Check(device->CreateShaderResourceView(resolved.texture,nullptr,&resolved.view),"Create resolved scene view");
        for(auto& b:bloom) {
            b.Reset(); d.Width=std::max(1u,d.Width/2); d.Height=std::max(1u,d.Height/2);
            b.width=d.Width;b.height=d.Height;
            Check(device->CreateTexture2D(&d,nullptr,&b.texture),"Create bloom surface");
            Check(device->CreateRenderTargetView(b.texture,nullptr,&b.target),"Create bloom target");
            Check(device->CreateShaderResourceView(b.texture,nullptr,&b.view),"Create bloom resource");
        }
    }
    void Text(const std::wstring& s,int x,int y,int size,int weight,COLORREF color,int tracking=0) {
        HFONT font=CreateFontW(-size,0,0,0,weight,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_TT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Segoe UI");
        HGDIOBJ old=SelectObject(dc,font); SetTextColor(dc,color); SetTextCharacterExtra(dc,tracking);
        if(x<0) { SIZE size{}; GetTextExtentPoint32W(dc,s.c_str(),int(s.size()),&size); x=(UIW-size.cx)/2; }
        TextOutW(dc,x,y,s.c_str(),int(s.size())); SetTextCharacterExtra(dc,0); SelectObject(dc,old); DeleteObject(font);
    }
    void Line(int x,int y,int w,COLORREF c,int thickness=1) {
        HPEN pen=CreatePen(PS_SOLID,thickness,c); auto old=SelectObject(dc,pen);
        MoveToEx(dc,x,y,nullptr); LineTo(dc,x+w,y); SelectObject(dc,old); DeleteObject(pen);
    }
    void UI(double t,bool menu,bool ready,bool paused,bool ended,bool hud,bool muted,bool noAudio,double noticeUntil) {
        memset(pixels,0,UIW*UIH*4);
        auto white=RGB(229,239,244),dim=RGB(120,152,169),cyan=RGB(110,225,219),gold=RGB(236,197,145);
        if(menu) {
            Text(L"A  P R O C E D U R A L  S P A C E  O D Y S S E Y",104,232,19,400,cyan);
            Text(L"AFTERLIGHT",94,271,115,200,white,3);
            Line(105,417,54,gold,2);
            Text(L"At the edge of everything,",104,447,27,300,white);
            Text(L"the universe remembers its first light.",104,485,27,300,white);
            Line(105,590,298,dim); Line(105,652,298,dim);
            Text(ready?L"ENTER  /  BEGIN TRANSMISSION":L"COMPOSING THE UNIVERSE...",106,610,16,600,white,1);
            Text(L"03:00   /   ONE CONTINUOUS JOURNEY   /   ORIGINAL SCORE",105,694,14,400,dim,1);
            Text(L"F11  FULLSCREEN",105,819,14,400,dim,1);
            Text(L"HEADPHONES RECOMMENDED",1206,819,14,400,dim,1);
            Text(L"A / L",1457,68,17,500,cyan,2);
        } else if(ended) {
            Text(L"T H E  S I G N A L  R E M A I N S",-1,312,18,400,cyan);
            Text(L"WE WERE HERE.",-1,363,80,200,white,2);
            Text(L"Every ending is the beginning of another sky.",-1,485,22,300,dim);
            Text(L"R  REPLAY     /     ESC  LEAVE",-1,624,16,500,white,1);
            Text(L"AFTERLIGHT   /   GENERATED FROM NOTHING BUT MATHEMATICS & SOUND",-1,819,13,400,dim,1);
        } else {
            if(t<12) {
                float a=1-Smooth(7.f,11.f,float(t));
                Text(L"AFTERLIGHT",91,73,20,400,RGB(int(180*a),int(210*a),int(218*a)),4);
            }
            if(hud) {
                Text(L"A / L",91,49,13,500,dim,2);
                int seconds=std::min(180,int(t)); wchar_t stamp[64]; swprintf(stamp,64,L"%02d:%02d  /  03:00",seconds/60,seconds%60);
                Text(stamp,1370,49,14,400,dim,1);
                Line(92,854,1416,RGB(37,53,65)); Line(92,854,int(1416*std::min(1.,t/180)),cyan,2);
                Text(L"SPACE  PAUSE     F11  FULLSCREEN     H  HIDE",92,869,11,400,dim,1);
                if(muted) Text(L"MUTED",1434,869,11,400,gold,1);
            }
            if(paused) { Text(L"TRANSMISSION PAUSED",-1,398,36,300,white,2); Text(L"SPACE  TO CONTINUE",-1,464,15,400,cyan,1); }
        }
        if(Clock()<noticeUntil) {
            std::wstring q=L"RENDER QUALITY  /  "+std::to_wstring(renderHeight)+L"p";
            Text(q,1130,95,16,500,cyan,1);
        }
        if(noAudio) Text(L"NO AUDIO DEVICE  /  VISUAL TRANSMISSION",102,103,14,500,gold,1);
        // Convert the antialiased GDI color coverage into straight-alpha RGBA.
        GdiFlush();
        for(size_t i=0;i<uiPixels.size();i++) {
            uint32_t p=pixels[i]; unsigned b=p&255,g=(p>>8)&255,r=(p>>16)&255,a=std::max({r,g,b});
            uiPixels[i]=a?((r*255/a)|((g*255/a)<<8)|((b*255/a)<<16)|(a<<24)):0;
        }
        context->UpdateSubresource(uiTexture,0,nullptr,uiPixels.data(),UIW*4,0);
    }
    void Draw(double time,bool menu,float validationBeat=-1.f) {
        ID3D11ShaderResourceView* none[8]={}; context->PSSetShaderResources(0,8,none);
        float pulse=validationBeat>=0.f?validationBeat:float(std::exp(-std::fmod(time,.5)*9));
        float data[]={float(renderWidth),float(renderHeight),float(time),pulse};
        context->UpdateSubresource(frameBuffer,0,nullptr,data,0,0); context->PSSetConstantBuffers(0,1,&frameBuffer);
        context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        context->VSSetShader(vertex,nullptr,0); context->PSSetShader(sceneShader,nullptr,0);
        context->PSSetSamplers(0,1,&sampler); context->PSSetShaderResources(7,1,&nursery.view);
        D3D11_VIEWPORT vp{0,0,float(renderWidth),float(renderHeight),0,1}; context->RSSetViewports(1,&vp);
        ID3D11RenderTargetView* sceneTargets[]={sceneTarget,geometryTarget};
        context->OMSetRenderTargets(2,sceneTargets,nullptr); context->Draw(3,0);
        context->PSSetShaderResources(7,1,none);
        ID3D11ShaderResourceView* finalScene=sceneView;
        if(time>=72.0 && time<120.0) {
            // Surface distance from the raymarch occludes rasterized matter;
            // a hardware depth buffer resolves the fragments against each other.
            context->OMSetRenderTargets(1,&sceneTarget,fragmentDepth);
            context->ClearDepthStencilView(fragmentDepth,D3D11_CLEAR_DEPTH,1.f,0);
            context->OMSetDepthStencilState(fragmentDepthState,0);
            context->RSSetState(fragmentRasterizer);
            context->PSSetShaderResources(0,1,&geometryView);
            context->VSSetConstantBuffers(0,1,&frameBuffer);
            context->VSSetShader(fragmentVertex,nullptr,0); context->PSSetShader(fragmentPixel,nullptr,0);
            context->DrawInstanced(36,24576,0,0);
            context->PSSetShaderResources(0,1,none);
            context->OMSetDepthStencilState(nullptr,0); context->RSSetState(nullptr);
            context->VSSetShader(vertex,nullptr,0);
            context->OMSetRenderTargets(1,&resolved.target,nullptr);
            context->PSSetShaderResources(0,1,&sceneView);
            context->PSSetShader(resolveShader,nullptr,0); context->Draw(3,0);
            context->PSSetShaderResources(0,1,none);
            finalScene=resolved.view;
        }
        context->PSSetShader(bloomShader,nullptr,0); context->PSSetSamplers(0,1,&sampler);
        context->PSSetConstantBuffers(1,1,&compositeBuffer);
        for(int i=0;i<5;i++) {
            context->PSSetShaderResources(0,8,none);
            auto& b=bloom[i];
            context->OMSetRenderTargets(1,&b.target,nullptr);
            ID3D11ShaderResourceView* input=i?bloom[i-1].view:finalScene;
            context->PSSetShaderResources(0,1,&input);
            float bd[]={1.f/float(i?bloom[i-1].width:renderWidth),1.f/float(i?bloom[i-1].height:renderHeight),i==0?1.f:0.f,0};
            context->UpdateSubresource(compositeBuffer,0,nullptr,bd,0,0);
            vp={0,0,float(b.width),float(b.height),0,1};context->RSSetViewports(1,&vp);context->Draw(3,0);
        }
        float clear[]={0,0,0,1}; context->ClearRenderTargetView(back,clear);
        float w=float(width),h=w*9/16; if(h>height) { h=float(height);w=h*16/9; }
        vp={float(width-w)/2,float(height-h)/2,w,h,0,1}; context->RSSetViewports(1,&vp);
        context->OMSetRenderTargets(1,&back,nullptr); context->PSSetShader(compositeShader,nullptr,0);
        ID3D11ShaderResourceView* srvs[]={finalScene,uiView,bloom[0].view,bloom[1].view,bloom[2].view,bloom[3].view,bloom[4].view}; context->PSSetShaderResources(0,7,srvs);
        context->PSSetSamplers(0,1,&sampler); float state[]={menu?1.f:0.f,float(time),0,0};
        context->UpdateSubresource(compositeBuffer,0,nullptr,state,0,0); context->PSSetConstantBuffers(1,1,&compositeBuffer); context->Draw(3,0);
    }
    std::vector<uint32_t> ReadFrame() {
        ID3D11Texture2D *buffer=nullptr,*staging=nullptr; Check(swap->GetBuffer(0,__uuidof(ID3D11Texture2D),(void**)&buffer),"Get capture buffer");
        D3D11_TEXTURE2D_DESC d{}; buffer->GetDesc(&d); d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ; d.MiscFlags=0;
        Check(device->CreateTexture2D(&d,nullptr,&staging),"Create capture staging"); context->CopyResource(staging,buffer);
        D3D11_MAPPED_SUBRESOURCE map{}; Check(context->Map(staging,0,D3D11_MAP_READ,0,&map),"Read capture");
        std::vector<uint32_t> result(width*height);
        for(UINT y=0;y<height;y++) memcpy(result.data()+y*width,(char*)map.pData+y*map.RowPitch,width*4);
        context->Unmap(staging,0); Release(staging); Release(buffer); return result;
    }
    void SaveBMP(const std::string& path) {
        auto p=ReadFrame(); for(auto& c:p) c=(c&0xFF00FF00)|((c&255)<<16)|((c>>16)&255);
        BITMAPFILEHEADER fh{}; BITMAPINFOHEADER ih{}; fh.bfType=0x4D42; fh.bfOffBits=sizeof(fh)+sizeof(ih); fh.bfSize=fh.bfOffBits+DWORD(p.size()*4);
        ih.biSize=sizeof(ih); ih.biWidth=width; ih.biHeight=-LONG(height); ih.biPlanes=1; ih.biBitCount=32; ih.biCompression=BI_RGB;
        FileOutput out(path.c_str()); out.Write(&fh,sizeof(fh)); out.Write(&ih,sizeof(ih)); out.Write(p.data(),p.size()*4); out.Close();
    }
    ~Renderer() {
        if(context) context->ClearState(); if(dc) { SelectObject(dc,oldBitmap); DeleteObject(bitmap); DeleteDC(dc); }
        Release(back); Release(sceneTarget); Release(sceneView); Release(sceneTexture); Release(uiView); Release(uiTexture);
        Release(geometryView); Release(geometryTarget); Release(geometryTexture);
        Release(fragmentDepth); Release(fragmentDepthTexture); Release(fragmentDepthState); Release(fragmentRasterizer);
        Release(fragmentVertex); Release(fragmentPixel); Release(nurseryShader); Release(resolveShader); nursery.Reset(); resolved.Reset();
        for(auto& b:bloom)b.Reset();
        Release(vertex); Release(sceneShader); Release(compositeShader); Release(bloomShader); Release(frameBuffer); Release(compositeBuffer); Release(sampler);
        Release(swap); Release(context); Release(device);
    }
};

struct App {
    HWND hwnd=nullptr; Renderer renderer; Audio audio;
    std::atomic<bool> ready{false}; HANDLE synth=nullptr; std::string synthError;
    bool running=true,menu=true,ended=false,hud=false,fullscreen=false,initialized=false,transportReady=false;
    bool minimized=false,noAudio=false; RECT savedRect{}; double noticeUntil=0;
    void Begin() { if(!transportReady) return; menu=false; ended=false; audio.Play(0); }
    void Fullscreen() {
        fullscreen=!fullscreen;
        if(fullscreen) { GetWindowRect(hwnd,&savedRect); MONITORINFO mi{sizeof(mi)}; GetMonitorInfo(MonitorFromWindow(hwnd,MONITOR_DEFAULTTONEAREST),&mi);
            SetWindowLongPtr(hwnd,GWL_STYLE,WS_POPUP|WS_VISIBLE); SetWindowPos(hwnd,HWND_TOP,mi.rcMonitor.left,mi.rcMonitor.top,mi.rcMonitor.right-mi.rcMonitor.left,mi.rcMonitor.bottom-mi.rcMonitor.top,SWP_FRAMECHANGED);
        } else { SetWindowLongPtr(hwnd,GWL_STYLE,WS_OVERLAPPEDWINDOW|WS_VISIBLE); SetWindowPos(hwnd,nullptr,savedRect.left,savedRect.top,savedRect.right-savedRect.left,savedRect.bottom-savedRect.top,SWP_FRAMECHANGED|SWP_NOZORDER); }
    }
    void Key(WPARAM k) {
        if(k==VK_ESCAPE) { running=false; return; }
        if(k==VK_F11 || (k==VK_RETURN&&(GetKeyState(VK_MENU)&0x8000))) { Fullscreen();return; }
        if(!initialized) return;
        if(k=='M') audio.Mute();
        if(k=='H') hud=!hud;
        if(k>='1'&&k<='3') { renderer.SetQuality(int(k-'0')); noticeUntil=Clock()+3; }
        if(k=='R') Begin();
        if(k==VK_SPACE||k==VK_RETURN) { if(menu||ended) Begin(); else audio.Pause(); }
        if((k==VK_RIGHT||k==VK_LEFT)&&!menu) { double t=std::clamp(audio.Time()+(k==VK_RIGHT?10.:-10.),0.,179.9); audio.Play(t); ended=false; }
    }
    static unsigned __stdcall Synthesize(void* opaque) {
        auto& app=*static_cast<App*>(opaque);
        try { app.audio.samples=Afterlight::GenerateSoundtrack(); }
        catch(const std::exception& e) { app.synthError=e.what(); }
        app.ready=true;
        return 0;
    }
    void StartSynthesizer() {
        synth=reinterpret_cast<HANDLE>(_beginthreadex(nullptr,0,Synthesize,this,0,nullptr));
        if(!synth) throw std::runtime_error("Cannot start soundtrack synthesis thread");
    }
    ~App() { if(synth) { WaitForSingleObject(synth,INFINITE); CloseHandle(synth); } }
};
static LRESULT CALLBACK WindowProc(HWND h,UINT m,WPARAM w,LPARAM l) {
    App* app=reinterpret_cast<App*>(GetWindowLongPtr(h,GWLP_USERDATA));
    if(m==WM_NCCREATE) { app=(App*)((CREATESTRUCT*)l)->lpCreateParams; SetWindowLongPtr(h,GWLP_USERDATA,(LONG_PTR)app); }
    if(app) {
        if(m==WM_CLOSE) { app->running=false; return 0; }
        if(m==WM_SYSKEYDOWN&&w==VK_F4) return DefWindowProc(h,m,w,l);
        if(m==WM_KEYDOWN||m==WM_SYSKEYDOWN) { if(!(l&(1LL<<30))) app->Key(w); return 0; }
        if(m==WM_DPICHANGED) { RECT* r=reinterpret_cast<RECT*>(l); SetWindowPos(h,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE); return 0; }
        if(m==WM_SIZE) { app->minimized=(w==SIZE_MINIMIZED); if(app->initialized&&!app->minimized) app->renderer.Resize(LOWORD(l),HIWORD(l)); return 0; }
        if(m==WM_LBUTTONDOWN&&app->menu) {
            RECT r; GetClientRect(h,&r); float vw=float(r.right),vh=vw*9/16; if(vh>r.bottom){vh=float(r.bottom);vw=vh*16/9;}
            float x=(short(LOWORD(l))-(r.right-vw)/2)*1600/vw,y=(short(HIWORD(l))-(r.bottom-vh)/2)*900/vh;
            if(x>=90&&x<=440&&y>=575&&y<=665) app->Begin();
        }
        if(m==WM_ERASEBKGND) return 1;
        if(m==WM_DESTROY) { PostQuitMessage(0); return 0; }
        if(m==WM_SETCURSOR && LOWORD(l)==HTCLIENT && app->fullscreen&&!app->menu) { SetCursor(nullptr); return TRUE; }
    }
    return DefWindowProc(h,m,w,l);
}
static void SaveWav(const std::string& path,const std::vector<int16_t>& samples) {
    FileOutput f(path.c_str()); auto u32=[&](uint32_t v){ f.Write(&v,4); }; auto u16=[&](uint16_t v){f.Write(&v,2);};
    uint32_t length=uint32_t(samples.size()*2); f.Write("RIFF",4);u32(length+36);f.Write("WAVEfmt ",8);u32(16);u16(1);u16(2);u32(Afterlight::SampleRate);u32(Afterlight::SampleRate*4);u16(4);u16(16);f.Write("data",4);u32(length);f.Write(samples.data(),length); f.Close();
}
int WINAPI WinMain(HINSTANCE instance,HINSTANCE,LPSTR,int) {
    SetProcessDPIAware();
    bool selftest=false,warp=false,capture=false,menuCapture=false,sequence=false,benchmark=false;
    double captureTime=15,sequenceStart=0,sequenceDuration=5;int sequenceFps=24,requestedQuality=0;
    std::string capturePath,wavPath,sequencePath;
    for(int i=1;i<__argc;i++) {
        std::string a=__argv[i]; if(a=="--self-test") selftest=true; else if(a=="--warp") warp=true;
        else if(a=="--capture"&&i+2<__argc) {capture=true;captureTime=atof(__argv[++i]);capturePath=__argv[++i];}
        else if(a=="--capture-menu"&&i+1<__argc) {capture=menuCapture=true;captureTime=14;capturePath=__argv[++i];}
        else if(a=="--export-wav"&&i+1<__argc) wavPath=__argv[++i];
        else if(a=="--quality"&&i+1<__argc) requestedQuality=std::clamp(atoi(__argv[++i]),1,3);
        else if(a=="--benchmark")benchmark=true;
        else if(a=="--sequence"&&i+4<__argc) { sequence=true;sequenceStart=atof(__argv[++i]);sequenceDuration=std::clamp(atof(__argv[++i]),.1,180.);sequenceFps=std::clamp(atoi(__argv[++i]),1,60);sequencePath=__argv[++i]; }
    }
    try {
        if(!wavPath.empty()) { SaveWav(wavPath,Afterlight::GenerateSoundtrack()); return 0; }
        App app;
        WNDCLASSEXW wc{}; wc.cbSize=sizeof(wc);wc.lpfnWndProc=WindowProc;wc.hInstance=instance;wc.lpszClassName=L"AfterlightDemo";
        wc.hCursor=LoadCursor(nullptr,IDC_ARROW);wc.hIcon=LoadIcon(instance,MAKEINTRESOURCE(1));if(!wc.hIcon)wc.hIcon=LoadIcon(nullptr,IDI_APPLICATION);wc.hIconSm=wc.hIcon;
        RegisterClassExW(&wc); RECT rect{0,0,1280,720}; AdjustWindowRect(&rect,WS_OVERLAPPEDWINDOW,FALSE);
        int x=std::max(0,int(GetSystemMetrics(SM_CXSCREEN)-(rect.right-rect.left))/2),y=std::max(0,int(GetSystemMetrics(SM_CYSCREEN)-(rect.bottom-rect.top))/2);
        app.hwnd=CreateWindowExW(0,wc.lpszClassName,L"AFTERLIGHT — a procedural space odyssey",WS_OVERLAPPEDWINDOW,x,y,rect.right-rect.left,rect.bottom-rect.top,nullptr,nullptr,instance,&app);
        if(!app.hwnd) throw std::runtime_error("Could not create window");
        app.renderer.Init(app.hwnd,warp); app.initialized=true;
        if(requestedQuality)app.renderer.SetQuality(requestedQuality);
        if(sequence||benchmark) {
            if(sequence) {
                CreateDirectoryA(sequencePath.c_str(),nullptr);app.renderer.Resize(960,540);
                int frames=int(sequenceDuration*sequenceFps);
                for(int i=0;i<frames;i++) {
                    double t=sequenceStart+double(i)/sequenceFps;
                    app.renderer.UI(t,false,true,false,t>=180,false,false,false,0);app.renderer.Draw(t,false);
                    char filename[128];snprintf(filename,sizeof(filename),"/frame%04d.bmp",i);
                    app.renderer.SaveBMP(sequencePath+filename);
                }
            }
            if(benchmark) {
                FileOutput report("build/benchmark.txt");report.Print("Adapter: %s\nInternal resolution: %ux%u\n",app.renderer.adapter.c_str(),app.renderer.renderWidth,app.renderer.renderHeight);
                for(double start:{14.,26.,44.,62.,65.5,84.,92.,104.,114.,123.,138.,143.5,145.5,148.,150.,156.,168.}) {
                    app.renderer.UI(start,false,true,false,false,false,false,false,0);
                    for(int i=0;i<3;i++){app.renderer.Draw(start,false);app.renderer.ReadFrame();}
                    double total=0,worst=0;const int count=30;
                    for(int i=0;i<count;i++) {double begin=Clock();app.renderer.Draw(start+i/30.,false);app.renderer.ReadFrame();double ms=(Clock()-begin)*1000.;total+=ms;worst=std::max(worst,ms);}
                    report.Print("Scene at %gs: mean=%gms; maximum=%gms\n",start,total/count,worst);report.Flush();
                }
                report.Close();
            }
            DestroyWindow(app.hwnd);return 0;
        }
        if(selftest||capture) {
            FileOutput report(selftest?"build/self-test.txt":nullptr); if(selftest) report.Print("AFTERLIGHT native validation\nAdapter: %s\nSoftware: %d\n",app.renderer.adapter.c_str(),int(app.renderer.software));
            if(capture) { app.renderer.UI(captureTime,menuCapture,true,false,captureTime>=180,false,false,false,0);app.renderer.Draw(captureTime,menuCapture);app.renderer.SaveBMP(capturePath); }
            if(selftest) {
                for(double t:{3.,14.,24.,29.,30.,31.,38.,44.,54.,60.,62.,64.,65.,66.,67.,72.,76.,84.,92.,100.,107.,108.,109.,114.,118.,120.,123.,136.,140.,143.,144.,145.,150.,156.,168.,177.}) {
                    app.renderer.UI(t,false,true,false,t>=180,false,false,false,0);double begin=Clock();app.renderer.Draw(t,false);
                    auto p=app.renderer.ReadFrame();double sum=0;size_t lit=0;for(uint32_t c:p) {double v=((c&255)+((c>>8)&255)+((c>>16)&255))/3.;sum+=v;if(v>10)lit++;}
                    report.Print("Frame %gs: mean=%g lit=%g render_ms=%g\n",t,sum/p.size(),double(lit)/p.size(),(Clock()-begin)*1000);
                    if(t<174&&lit<p.size()/100) throw std::runtime_error("Self-test: unexpectedly blank scene");
                }
                // Infinitesimal time changes must not expose a renderer/pass
                // boundary. Hold the intentional kick-light attack constant
                // so the check measures the handoff rather than a music beat.
                for(double boundary:{66.,72.,118.,120.,150.}) {
                    app.renderer.UI(boundary,false,true,false,false,false,false,false,0);
                    app.renderer.Draw(boundary-.0001,false,1.f);auto before=app.renderer.ReadFrame();
                    app.renderer.Draw(boundary+.0001,false,1.f);auto after=app.renderer.ReadFrame();
                    double difference=0;
                    for(size_t i=0;i<before.size();i++)for(int shift:{0,8,16})
                        difference+=std::abs(int((before[i]>>shift)&255)-int((after[i]>>shift)&255));
                    difference/=before.size()*3.;
                    report.Print("Continuity at %gs: mean RGB difference=%g / 255\n",boundary,difference);report.Flush();
                    if(difference>1.0)throw std::runtime_error("Self-test: discontinuity at renderer handoff");
                }
                double begin=Clock();app.StartSynthesizer();
                if(WaitForSingleObject(app.synth,INFINITE)!=WAIT_OBJECT_0 || !app.ready) throw std::runtime_error("Self-test: synthesis thread failed");
                if(!app.synthError.empty()) throw std::runtime_error(app.synthError);
                auto music=std::move(app.audio.samples); double peak=0,sum=0; size_t clips=0;
                for(int16_t n:music) {double x=n/32768.;peak=std::max(peak,std::abs(x));sum+=x*x;if(n==32767||n==-32768)clips++;}
                report.Print("Audio: samples=%zu peak=%g rms=%g clipped=%zu generation_seconds=%g\n",music.size(),peak,sqrt(sum/music.size()),clips,Clock()-begin);
                if(music.size()!=size_t(Afterlight::Duration*Afterlight::SampleRate)*2||clips||peak<.01) throw std::runtime_error("Self-test: invalid soundtrack");
                app.audio.samples=std::move(music); bool audioOpen=app.audio.Open();report.Print("waveOut device: %s\n",audioOpen?"available":"unavailable (visual-only fallback)");
                if(audioOpen) { app.audio.Play(0); Sleep(140); double before=app.audio.Time();app.audio.Pause();Sleep(100);double held=app.audio.Time();app.audio.Pause();Sleep(100);double resumed=app.audio.Time();app.audio.Play(90);Sleep(100);double sought=app.audio.Time();app.audio.Stop();report.Print("Audio clock: before=%g paused=%g resumed=%g seek=%g\n",before,held,resumed,sought);if(before<=0||std::abs(held-before)>.04||resumed<=held||sought<90||sought>91)throw std::runtime_error("Self-test: audio transport clock failed");}
                app.renderer.SetQuality(1);app.renderer.Resize(960,600);app.renderer.Draw(44,false);auto resized=app.renderer.ReadFrame();
                if(resized.size()!=960*600||app.renderer.renderHeight!=540)throw std::runtime_error("Self-test: resolution switching failed");
                app.renderer.Draw(92,false); app.renderer.ReadFrame();
                app.renderer.SetQuality(3);app.renderer.Draw(156,false);app.renderer.ReadFrame();
                app.renderer.UI(92,false,true,false,false,false,false,false,0);
                app.renderer.Draw(92,false);auto firstVisit=app.renderer.ReadFrame();
                app.renderer.Draw(168,false);app.renderer.ReadFrame();
                app.renderer.Draw(92,false);auto returnVisit=app.renderer.ReadFrame();
                if(firstVisit!=returnVisit)throw std::runtime_error("Self-test: procedural seeking depends on frame history");
                report.Print("Deterministic seek: fragment frame 92s identical after visiting nursery at 168s\n");
                report.Print("Resolution changes: 540p and 1080p rendered; 960x600 letterboxed resize passed\nPASS\n");
                report.Close();
            }
            DestroyWindow(app.hwnd); return 0;
        }
        ShowWindow(app.hwnd,SW_SHOW); UpdateWindow(app.hwnd);
        app.StartSynthesizer();
        bool opened=false; double uiLast=-1,menuStart=Clock();
        while(app.running) {
            MSG msg; while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)) {if(msg.message==WM_QUIT)app.running=false;TranslateMessage(&msg);DispatchMessageW(&msg);}
            if(!app.running)break;
            if(app.ready&&!opened) { if(!app.synthError.empty())throw std::runtime_error(app.synthError);app.noAudio=!app.audio.Open();opened=true;app.transportReady=true;if(app.audio.muted&&app.audio.device)waveOutSetVolume(app.audio.device,0); }
            if(app.minimized) { Sleep(30);continue; }
            double now=Clock();double t=app.menu?14+std::sin((now-menuStart)*.06)*3:app.audio.Time();
            if(!app.menu&&!app.ended&&t>=179.95) {app.ended=true;app.audio.Stop();app.audio.offset=180;t=180;}
            if(now-uiLast>.05) {app.renderer.UI(t,app.menu,opened,app.audio.paused,app.ended,app.hud,app.audio.muted,app.noAudio,app.noticeUntil);uiLast=now;}
            app.renderer.Draw(t,app.menu);
            HRESULT present=app.renderer.swap->Present(1,0);if(present==DXGI_STATUS_OCCLUDED)Sleep(50);else Check(present,"Present frame");
        }
        app.audio.Stop();DestroyWindow(app.hwnd);return 0;
    } catch(const std::exception& e) {
        // Error reporting must not throw if the current directory is read-only.
        if(FILE* log=fopen("afterlight-error.txt","wb")) { fprintf(log,"%s\n",e.what()); fclose(log); }
        if(!selftest&&!capture&&!sequence&&!benchmark)MessageBoxA(nullptr,e.what(),"AFTERLIGHT",MB_OK|MB_ICONERROR);
        return 1;
    }
}
