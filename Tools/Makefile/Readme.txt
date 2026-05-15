How to use make to build the Programm and to create a bootable ADF with "make" and "amitools/xdftool" under Windows

Prerequisites:

- make.exe (from git, Visual Studio, MinGW etc.)
- min. Python 3.9 installed

1) Install AmiTools in Python
    https://github.com/cnvogelg/amitools
    pip3 install amitools

2) Add Python Scriptfolder to Path-Variable
    for example: %AppData%\Local\Python\pythoncore-3.14-64\Scripts

3) Modify the example "Makefile.mak" file to your needs and drop it (and the cmd files) in your project Folder.

4) Run the appropriate cmd (build/adf)


