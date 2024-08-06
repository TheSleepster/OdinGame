@echo off

set compilerflags=-o:none -show-timings -out:"Sharp.exe" -debug -build-mode:exe -vet-cast

IF NOT EXIST ..\build mkdir ..\build
pushd ..\build
odin build ..\code\ %compilerflags%
popd
