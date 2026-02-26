## Installing chromedriver on mac

Chrome updates all the time, and so does chromedriver. 

This script checks your installed Google Chrome version and downloads, extracts, and symlinks the relevant chromedriver into ./bin

To use:
```sh
./install_chromedriver.rb
export PATH=$PATH:$(pwd)/bin
```

and add the bin folder to your path in your shell's rc file
