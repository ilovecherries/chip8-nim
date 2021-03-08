import sugar, algorithm, random
import streams
import sdl2

# reference: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

const
  DisplayX = 64
  DisplayY = 32
  VramSize = DisplayY
  RamSize = (0xFFF - 0x200)
  StackSize = 0x16
  VariablesSize = 0x10
  KeyboardSize = 0x10
  InstructionSize = 4 # nibbles

type
  Chip8Program = ref object
    vram: array[VramSize, uint64]
    ram: array[RamSize, byte]
    stack: array[StackSize, uint32]
    stackPosition: uint8
    vars: array[VariablesSize, uint8]
    keyboard: array[KeyboardSize, uint8]
    i: uint16
    endPoint: uint32

var Chip8InstructionPointers: array[0x10, ((Chip8Program, var uint16) -> void)]

template chip8Instruction(mask: SomeInteger, prg: untyped, ins: untyped, body: untyped) =
  Chip8InstructionPointers[mask] = proc (prg: Chip8Program, ins: var uint16): void =
    body

proc getNibble(prg: Chip8Program, i: SomeInteger): byte =
  return prg.ram[(i div 2)] shr (4 * cast[int](i mod 2 == 0)) and 0xF

proc getInstruction(prg: Chip8Program, i: uint32): uint16 =
  if (i mod 2) == 1:
    return (cast[uint16](prg.ram[(i div 2)+1]) shl 4) or 
           (cast[uint16](prg.ram[(i div 2)+2]) shr 4) or 
           (cast[uint16](prg.ram[i div 2]) shl 12)
  else:
    return (cast[uint16](prg.ram[(i div 2)+1]) shl 0) or (cast[uint16](prg.ram[i div 2]) shl 8)

chip8Instruction(0, prg, ins):
  case cast[byte](ins and 0xFF):
    # 00E0 - CLS
    # Clear the display.
    of 0x00E0: 
      prg.vram.fill(0)
    # 00EE - RET
    # Return from a subroutine.
    # The interpreter sets the program counter to the address at the top of the stack, then subtracts 1 from the stack pointer.
    of 0x00EE:
      dec prg.stackPosition
      assert prg.stackPosition >= 0, "The stack position has been decreased too many times!"
    # 0nnn - SYS addr
    # IGNORE THIS
    else:
      return

# 1nnn - JP addr
# Jump to location nnn.
# The interpreter sets the program counter to nnn.
chip8Instruction(1, prg, ins):
  prg.stack[prg.stackPosition] = (ins and 0x0FFF) - InstructionSize

# 2nnn - CALL addr
# Call subroutine at nnn.
# The interpreter increments the stack pointer, then puts the current PC on the top of the stack. The PC is then set to nnn.
chip8Instruction(2, prg, ins):
  inc prg.stackPosition
  assert prg.stackPosition <= StackSize, "The stack pointer has been increased too many times!"
  prg.stack[prg.stackPosition] = (ins and 0x0FFF) - InstructionSize

# 3xkk - SE Vx, byte
# Skip next instruction if Vx = kk.
# The interpreter compares register Vx to kk, and if they are equal, increments the program counter by 2.
chip8Instruction(3, prg, ins):
  let
    variable = ins shr 8 and 0xF
    value = ins and 0xFF
  if prg.vars[variable] == value:
    prg.stack[prg.stackPosition] += InstructionSize

# 4xkk - SNE Vx, byte
# Skip next instruction if Vx != kk.
# The interpreter compares register Vx to kk, and if they are not equal, increments the program counter by 2.
chip8Instruction(4, prg, ins):
  let
    variable = prg.vars[ins shr 8 and 0xF]
    value = ins and 0xFF
  if variable != value:
    prg.stack[prg.stackPosition] += InstructionSize

# 5xy0 - SE Vx, Vy
# Skip next instruction if Vx = Vy.
# The interpreter compares register Vx to register Vy, and if they are equal, increments the program counter by 2.
chip8Instruction(5, prg, ins):
  let 
    variableX = prg.vars[ins shr 8 and 0xF]
    variableY = prg.vars[ins shr 4 and 0xF]
  if variableX == variableY:
    prg.stack[prg.stackPosition] += InstructionSize

# 6xkk - LD Vx, byte
# Set Vx = kk.
# The interpreter puts the value kk into register Vx.
chip8Instruction(6, prg, ins):
  let 
    variable = ins shr 8 and 0xF
    value = cast[uint8](ins and 0xFF)
  prg.vars[variable] = value

# 7xkk - ADD Vx, byte
# Set Vx = Vx + kk.
# Adds the value kk to the value of register Vx, then stores the result in Vx.
chip8Instruction(7, prg, ins):
  let 
    variable = ins shr 8 and 0xF
    value = cast[uint8](ins and 0xFF)
  prg.vars[variable] += value

chip8Instruction(8, prg, ins):
  type VariableOperations = enum
    LD, OR, AND, XOR, ADD, SUB, SHR, SUBN, SHL
  let
    variableX = ins shr 8 and 0xF
    variableY = ins shr 4 and 0xF
    instruction = (ins and 0xF)
  case VariableOperations(instruction):
    # 8xy0 - LD Vx, Vy
    # Set Vx = Vy.
    # Stores the value of register Vy in register Vx.
    of VariableOperations.LD:
      prg.vars[variableX] = prg.vars[variableY]
    # 8xy1 - OR Vx, Vy
    # Set Vx = Vx OR Vy.
    # Performs a bitwise OR on the values of Vx and Vy, then stores 
    # the result in Vx.
    of VariableOperations.OR:
      prg.vars[variableX] = prg.vars[variableX] or prg.vars[variableY]
    # 8xy2 - AND Vx, Vy
    # Set Vx = Vx AND Vy.
    # Performs a bitwise AND on the values of Vx and Vy, then stores 
    # the result in Vx.
    of VariableOperations.AND:
      prg.vars[variableX] = prg.vars[variableX] and prg.vars[variableY]
    # 8xy3 - XOR Vx, Vy
    # Set Vx = Vx XOR Vy.
    # Performs a bitwise exclusive OR on the values of Vx and Vy, then stores the result in Vx.
    of VariableOperations.XOR:
      prg.vars[variableX] = prg.vars[variableX] xor prg.vars[variableY]
    # 8xy4 - ADD Vx, Vy
    # Set Vx = Vx + Vy, set VF = carry.
    # The values of Vx and Vy are added together. If the result is greater than 8 bits (i.e., > 255,)
    # VF is set to 1, otherwise 0. Only the lowest 8 bits of the result are kept, and stored in Vx.
    of VariableOperations.ADD:
      let res = cast[int16](prg.vars[variableX] + prg.vars[variableY])
      prg.vars[0xF] = if res > 255: 1 else: 0
      prg.vars[variableX] = cast[uint8](res and 0xFF)
    # 8xy5 - SUB Vx, Vy
    # Set Vx = Vx - Vy, set VF = NOT borrow.
    # If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is subtracted from Vx, and the
    # results stored in Vx.
    of VariableOperations.SUB:
      prg.vars[0xF] = if prg.vars[variableX] > prg.vars[variableY]: 1 else: 0
      prg.vars[variableX] = prg.vars[variableX] - prg.vars[variableY]
    # 8xy6 - SHR Vx {, Vy}
    # Set Vx = Vx SHR 1.
    # If the least-significant bit of Vx is 1, then VF is set to 1, otherwise 0. 
    # Then Vx is divided by 2.
    of VariableOperations.SHR:
      prg.vars[0xF] = prg.vars[variableX] and 1
      prg.vars[variableX] = (prg.vars[variableX] shr 1) div 2
    # 8xy7 - SUBN Vx, Vy
    # Set Vx = Vy - Vx, set VF = NOT borrow.
    # If Vy > Vx, then VF is set to 1, otherwise 0. Then Vx is subtracted from 
    # Vy, and the results stored in Vx.
    of VariableOperations.SUBN:
      prg.vars[0xF] = if prg.vars[variableX] < prg.vars[variableY]: 1 else: 0
      prg.vars[variableX] = prg.vars[variableX] - prg.vars[variableY]
    # 8xyE - SHL Vx {, Vy}
    # Set Vx = Vx SHL 1.
    # If the most-significant bit of Vx is 1, then VF is set to 1, otherwise to 0.
    # Then Vx is multiplied by 2.S
    of VariableOperations.SHL:
      prg.vars[0xF] = (prg.vars[variableX] shr 7) and 1
      prg.vars[variableX] = (prg.vars[variableX] shl 1) * 2

# 9xy0 - SNE Vx, Vy
# Skip next instruction if Vx != Vy.
# The values of Vx and Vy are compared, and if they are not equal,
# the program counter is increased by 2.
chip8Instruction(9, prg, ins):
  let 
    variableX = ins shr 8 and 0xF
    variableY = ins shr 4 and 0xF
  if prg.vars[variableX] != prg.vars[variableY]:
    inc prg.stack[prg.stackPosition]

# Annn - LD I, addr
# Set I = nnn.
# The value of register I is set to nnn.
chip8Instruction(0xA, prg, ins):
  prg.i = ins and 0xFFF

# Bnnn - JP V0, addr
# Jump to location nnn + V0.
# The program counter is set to nnn plus the value of V0.
chip8Instruction(0xB, prg, ins):
  prg.stack[prg.stackPosition] = prg.vars[0] + (ins and 0xFFF) - InstructionSize

# Cxkk - RND Vx, byte
# Set Vx = random byte AND kk.
# The interpreter generates a random number from 0 to 255, which is then ANDed 
# with the value kk. The results are stored in Vx.
chip8Instruction(0xC, prg, ins):
  let
    variable = (ins and 0xF00) shr 8
    value = cast[uint8](ins and 0xFF)
    randomNumber: uint8 = cast[uint8](rand(256))
  prg.vars[variable] = value and randomNumber

# Dxyn - DRW Vx, Vy, nibble
# Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
chip8Instruction(0xD, prg, ins):
  let
    x = prg.vars[ins shr 8 and 0xF]
    y = prg.vars[ins shr 4 and 0xF]
    n = ins and 0xF
  echo "..."
  # iterate through all bytes
  for i in cast[uint64](0)..<n:
    let 
      vramPosition = (y + i) mod DisplayY
      mask = cast[uint64](prg.getNibble(prg.i + i)) shl (60 - x)
    # FIXME: THIS DOES NOT WRAP AROUND THE X AXIS, NEED TO FIX
    # THIS IS JUST A QUICK IMPLEMENTATION SO THAT WE CAN SEE RESULTS
    prg.vram[vramPosition] = prg.vram[vramPosition] xor mask

proc cycle(prg: Chip8Program): void =
  let pos = prg.stack[prg.stackPosition]
  var 
    instructionMask = prg.getNibble(pos)
    instruction = prg.getInstruction(pos)
  Chip8InstructionPointers[instructionMask](prg, instruction)
  prg.stack[prg.stackPosition] += InstructionSize

proc drawToRenderer(prg: Chip8Program, renderer: RendererPtr): void =
  renderer.setDrawColor 0, 0, 0, 255
  renderer.clear()
  for i in countup(0, DisplayY - 1):
    for j in countdown(DisplayX - 1, 0):
      var r = rect(DisplayX - 1 - cint(j), cint(i), cint(1), cint(1))
      if (prg.vram[i] shr j and 1) != 0:
        renderer.fillRect(r)
  renderer.setDrawColor 255, 255, 255, 255
  renderer.present()

when isMainModule:
  proc main(): void =
    # prepare interpreter
    var 
      program = Chip8Program()
      s = newFileStream("BC_test.ch8", fmRead)
      index = 0
    while not s.atEnd:
      program.ram[index] = s.readChar.byte
      inc index
    program.endPoint = cast[uint32](index div 2)

    # initialize sdl things
    discard sdl2.init(INIT_EVERYTHING)
    defer: sdl2.quit()

    let window = createWindow("Pong", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, DisplayX, DisplayY, SDL_WINDOW_SHOWN)
    defer: window.destroy()

    let renderer = createRenderer(window, -1, Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture)
    defer: renderer.destroy()
    var running = true

    while program.stack[program.stackPosition] < program.endPoint:
      program.cycle()

    # while running and program.stack[program.stackPosition] < program.endPoint:
    #   var event = defaultEvent
    #   while pollEvent(event):
    #     case event.kind:
    #       of QuitEvent:
    #         running = false
    #       else:
    #         discard
    #   program.cycle()
    #   program.drawToRenderer(renderer)
    
    # while running:
    #   var event = defaultEvent
    #   while pollEvent(event):
    #     case event.kind:
    #       of QuitEvent:
    #         running = false
    #       else:
    #         discard
  
  main()