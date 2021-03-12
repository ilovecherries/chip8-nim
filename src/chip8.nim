when defined(js):
  import dom
else:
  import sdl2, os, streams
import interpreter

# reference: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

const
  Framerate = 60
  MillisecondPerFrame = 1000 / Framerate
  ResolutionMultiplier = 16
when defined(js):
  const
    KeyboardCodes = [
      49, 50, 51, 52,
      81, 87, 69, 82,
      65, 83, 68, 70,
      90, 88, 67, 86
    ]
    # Contains the data for the test ROM for use in the Javascript backend
    TestData="Ek7qrKrqzqqqruCgoODAQEDg4CDA4OBgIOCg4CAgYEAgQOCA4ODgICAg4OCg4ODgIOBAoOCg4MCA4OCAwICgQKCgogLatADuogLatBPcaAFpBWoKawFlKmYrohbYtKI+2bSiAjYrogbatGsGohrYtKI+2bSiBkUqogLatGsLoh7YtKI+2bSiBlVgogLatGsQoibYtKI+2bSiBnb/RiqiAtq0axWiLti0oj7ZtKIGlWCiAtq0axqiMti0oj7ZtCJCaBdpG2ogawGiCti0ojbZtKIC2rRrBqIq2LSiCtm0ogaHUEcqogLatGsLoirYtKIO2bSiBmcqh7FHK6IC2rRrEKIq2LSiEtm0ogZmeGcfh2JHGKIC2rRrFaIq2LSiFtm0ogZmeGcfh2NHZ6IC2rRrGqIq2LSiGtm0ogZmjGeMh2RHGKIC2rRoLGkwajRrAaIq2LSiHtm0ogZmjGd4h2VH7KIC2rRrBqIq2LSiItm0ogZm4IZuRsCiAtq0awuiKti0ojbZtKIGZg+GZkYHogLatGsQojrYtKIe2bSj6GAAYTDxVaPp8GWiBkAwogLatGsVojrYtKIW2bSj6GaJ9jPyZaICMAGiBjEDogYyB6IG2rRrGqIO2LSiPtm0EkgT3A=="
else:
  const
    KeyboardCodes = [
      SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4,
      SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_E, SDL_SCANCODE_R,
      SDL_SCANCODE_A, SDL_SCANCODE_S, SDL_SCANCODE_D, SDL_SCANCODE_F,
      SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_C, SDL_SCANCODE_V
    ]


proc drawToRenderer(prg: Chip8, renderer: RendererPtr): void =
  renderer.setDrawColor(0, 0, 0, 255)
  renderer.clear()
  renderer.setDrawColor(255, 255, 255, 255)
  for i in countup(0, DisplayY - 1):
    for j in countdown(DisplayX - 1, 0):
      var r = rect(
        ResolutionMultiplier*(DisplayX - 1 - cint(j)),
        cint(i*ResolutionMultiplier),
        cint(1*ResolutionMultiplier),
        cint(1*ResolutionMultiplier)
      )
      if (prg.vram[i][j] and 1) != 0:
        renderer.fillRect(r)
  renderer.present()


when isMainModule:
  when defined(js):
    var program: Chip8
    proc chip8load(): void {.exportc.} =
      program = newChip8()
      var
        index = 0x200
        data = decode(TestRom)
      for i in countup(0, data.len-1):
        program.ram[index + i] = cast[byte](data[i])
        program.endPoint = cast[uint32](index + i)
    proc chip8cycle(): void {.exportc.} =
      program.cycle()
    proc chip8getvram(): array[DisplayY, array[DisplayX, uint8]] {.exportc.} =
      return program.vram
  else:
    proc main(): void =
      # prepare interpreter
      var romFile = "chip8-test-rom/test_opcode.ch8"
      if paramCount() == 1:
        romFile = paramStr(1)
      var 
        program = newChip8()
        s = newFileStream(romFile, fmRead)
        index = 0x200
      while not s.atEnd:
        program.ram[index] = s.readChar.byte
        inc index
        program.stack[0] = 0x200
        program.endPoint = cast[uint32](index)
            
      # initialize sdl things
      discard sdl2.init(INIT_EVERYTHING)
      defer: sdl2.quit()
      
      let window = createWindow(
        "CHIP-8",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        DisplayX*ResolutionMultiplier,
        DisplayY*ResolutionMultiplier,
        SDL_WINDOW_SHOWN
      )
      defer: window.destroy()
      
      let renderer = createRenderer(
        window,
        -1,
        Renderer_Accelerated or Renderer_TargetTexture
      )
      defer: renderer.destroy()
      var
        running = true
        lastTime: uint32 = 0
      program.dt = 60
        
      while running and program.stack[program.stackPosition] < program.endPoint:
        while (lastTime - sdl2.getTicks() < cast[uint32](MillisecondPerFrame)):
          program.cycle()
          sdl2.delay(1)
        var event = defaultEvent
        while pollEvent(event):
          case event.kind:
            of QuitEvent:
              running = false
            of KeyDown:
              let code = KeyboardCodes.find(event.key.keysym.scancode)
              if code != -1:
                program.keyboard[code] = true
            of KeyUp:
              let code = KeyboardCodes.find(event.key.keysym.scancode)
              if code != -1:
                program.keyboard[code] = false
            else:
              discard
        program.dt -= 1
        if program.dt == 255: program.dt = 60
        program.drawToRenderer(renderer)
        lastTime = sdl2.getTicks()
            
    main()