How to create a bootable ADF with "make" and "amitools/xdftool" under Windows

Prerequisites:

- make.exe (from git, Visual Studio, MinGW etc.)
- min. Python 3.9 installed

1) Install AmiTools in Python
    https://github.com/cnvogelg/amitools
    pip3 install amitools

2) Add Python Scriptfolder to Path-Variable
    for example: %AppData%\Local\Python\pythoncore-3.14-64\Scripts

3) Modify the example "MakeADF.mak" file to your needs and drop it in your project folder

4) Run make
    make -f MakeADF.mak adf
