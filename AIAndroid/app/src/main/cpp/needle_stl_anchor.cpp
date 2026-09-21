// Single C++ translation unit whose only job is to make CMake link the NDK
// STL into libneedlejni.so — libneedle.a is a C++ archive and the toolchain
// attaches c++_static only to targets containing C++ sources. Keep empty.
