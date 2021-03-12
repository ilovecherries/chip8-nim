import streams, sdl2, os
import interpreter

# reference: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

const
  Framerate = 60
  MillisecondPerFrame = 1000 / Framerate
  ResolutionMultiplier = 16
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
      if (prg.vram[i] shr j and 1) != 0:
        renderer.fillRect(r)
  renderer.present()


when isMainModule:
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
