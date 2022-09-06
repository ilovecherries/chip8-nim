# Package

version       = "0.1.0"
author        = "ilovecherries"
description   = "chip-8 interpreter"
license       = "MIT"
srcDir        = "src"
bin           = @["chip8"]
backend       = "c"

# Dependencies

requires "nim >= 1.4.2"
requires "sdl2"
