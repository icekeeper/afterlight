#pragma once
#include <cstdarg>
#include <cstdio>
#include <stdexcept>

// Diagnostics need simple byte writes and printf formatting, not the complete
// locale/iostream machinery. Keep exports checked, including the final flush.
class FileOutput {
    FILE* file=nullptr;
public:
    explicit FileOutput(const char* path) {
        if(path && !(file=fopen(path,"wb"))) throw std::runtime_error("Cannot open output file");
    }
    FileOutput(const FileOutput&)=delete;
    FileOutput& operator=(const FileOutput&)=delete;
    ~FileOutput() { if(file) fclose(file); }
    void Write(const void* data,size_t size) {
        if(fwrite(data,1,size,file)!=size) throw std::runtime_error("Cannot write output file");
    }
    void Print(const char* format,...) {
        va_list arguments; va_start(arguments,format);
        int result=vfprintf(file,format,arguments); va_end(arguments);
        if(result<0) throw std::runtime_error("Cannot write diagnostic report");
    }
    void Flush() {
        if(fflush(file)!=0) throw std::runtime_error("Cannot flush output file");
    }
    void Close() {
        FILE* closing=file; file=nullptr;
        if(closing && fclose(closing)!=0) throw std::runtime_error("Cannot finish output file");
    }
};
