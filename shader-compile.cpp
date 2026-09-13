#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3dcompiler.h>
#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
    const char* path=argc>1?argv[1]:"scene.hlsl";
    FILE* f=fopen(path,"rb");
    if(!f){fprintf(stderr,"Cannot read %s\n",path);return 1;}
    fseek(f,0,SEEK_END);long length=ftell(f);rewind(f);
    char* source=(char*)malloc((size_t)length);
    if(!source||fread(source,1,(size_t)length,f)!=(size_t)length){fclose(f);return 2;}
    fclose(f);
    ID3DBlob* bytecode=nullptr;
    ID3DBlob* errors=nullptr;
    DWORD start=GetTickCount();
    const char* entry=argc>3?argv[3]:"PSMain";
    const char* model=argc>4?argv[4]:"ps_4_0";
    HRESULT hr=D3DCompile(source,(size_t)length,path,nullptr,D3D_COMPILE_STANDARD_FILE_INCLUDE,entry,model,D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&bytecode,&errors);
    fprintf(stdout,"D3DCompile %s/%s: HRESULT 0x%08lX; %lu ms\n",entry,model,(unsigned long)hr,(unsigned long)(GetTickCount()-start));
    if(errors){fwrite(errors->GetBufferPointer(),1,errors->GetBufferSize(),stderr);errors->Release();}
    if(bytecode){
        fprintf(stdout,"Compiled bytecode: %zu bytes\n",bytecode->GetBufferSize());
        if(SUCCEEDED(hr)&&argc>2){
            FILE* out=fopen(argv[2],"wb");
            if(!out){fprintf(stderr,"Cannot write %s\n",argv[2]);bytecode->Release();free(source);return 4;}
            size_t wrote=fwrite(bytecode->GetBufferPointer(),1,bytecode->GetBufferSize(),out);
            fclose(out);
            if(wrote!=bytecode->GetBufferSize()){bytecode->Release();free(source);return 5;}
        }
        bytecode->Release();
    }
    free(source);
    return FAILED(hr)?3:0;
}
