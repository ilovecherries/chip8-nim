import sugar, algorithm

# reference: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

const
  DisplayX = 64
  DisplayY = 32
  VramSize = DisplayY
  RamSize = ((0xFFF - 0x200) / 2).toInt
  StackSize = 0x16
  VariablesSize = 0x10
  KeyboardSize = 0x10
  InstructionSize = 2 # bytes

type
  Chip8Program = ref object
    vram: array[VramSize, uint64]
    ram: array[RamSize, byte]
    stack: array[StackSize, uint32]
    stackPosition: uint8
    vars: array[VariablesSize, uint8]
    keyboard: array[KeyboardSize, uint8]

var Chip8InstructionPointers: array[0x10, ((Chip8Program, var uint16) -> void)]

template chip8Instruction(mask: SomeInteger, prg: untyped, ins: untyped, body: untyped) =
  Chip8InstructionPointers[mask] = proc (prg: Chip8Program, ins: var uint16): void =
    body

chip8Instruction(0, prg, ins):
  type SystemCalls = enum
    CLS = 0x00E0, RET = 0x00EE
  case SystemCalls(ins and 0xFF):
    # 00E0 - CLS
    # Clear the display.
    of SystemCalls.CLS: 
      prg.vram.fill(0)
    # 00EE - RET
    # Return from a subroutine.
    # The interpreter sets the program counter to the address at the top of the stack, then subtracts 1 from the stack pointer.
    of SystemCalls.RET:
      dec prg.stackPosition
      assert prg.stackPosition >= 0, "The stack position has been decreased too many times!"

# 1nnn - JP addr
# Jump to location nnn.
# The interpreter sets the program counter to nnn.
chip8Instruction(1, prg, ins):
  prg.stack[prg.stackPosition] = ins and 0x0FFF

# 2nnn - CALL addr
# Call subroutine at nnn.
# The interpreter increments the stack pointer, then puts the current PC on the top of the stack. The PC is then set to nnn.
chip8Instruction(2, prg, ins):
  inc prg.stackPosition
  assert prg.stackPosition <= StackSize, "The stack pointer has been increased too many times!"
  prg.stack[prg.stackPosition] = ins and 0x0FFF

# 3xkk - SE Vx, byte
# Skip next instruction if Vx = kk.
# The interpreter compares register Vx to kk, and if they are equal, increments the program counter by 2.
chip8Instruction(3, prg, ins):
  let
    variable = (ins and 0xF00) shr 8
    value = ins and 0xFF
  if prg.vars[variable] == value:
    inc prg.stack[prg.stackPosition]

# 4xkk - SNE Vx, byte
# Skip next instruction if Vx != kk.
# The interpreter compares register Vx to kk, and if they are not equal, increments the program counter by 2.
chip8Instruction(4, prg, ins):
  let
    variable = prg.vars[(ins and 0xF00) shr 8]
    value = ins and 0xFF
  if variable != value:
    inc prg.stack[prg.stackPosition]

# 5xy0 - SE Vx, Vy
# Skip next instruction if Vx = Vy.
# The interpreter compares register Vx to register Vy, and if they are equal, increments the program counter by 2.
chip8Instruction(5, prg, ins):
  let 
    variableX = prg.vars[(ins and 0xF00) shr 8]
    variableY = prg.vars[(ins and 0xF0) shr 4]
  if variableX == variableY:
    inc prg.stack[prg.stackPosition]

# 6xkk - LD Vx, byte
# Set Vx = kk.
# The interpreter puts the value kk into register Vx.
chip8Instruction(6, prg, ins):
  let 
    variable = (ins and 0xF00) shr 8
    value = cast[uint8](ins and 0xFF)
  prg.vars[variable] = value

# 7xkk - ADD Vx, byte
# Set Vx = Vx + kk.
# Adds the value kk to the value of register Vx, then stores the result in Vx.
chip8Instruction(7, prg, ins):
  let 
    variable = (ins and 0xF00) shr 8
    value = cast[uint8](ins and 0xFF)
  prg.vars[variable] += value

chip8Instruction(8, prg, ins):
  type VariableOperations = enum
    LD, OR, AND, XOR, ADD, SUB, SHR, SUBN, SHL

proc getInstruction(prg: Chip8Program, index: uint32): uint16 =
  return (cast[uint16](prg.ram[index+1]) shl 0) or 
         (cast[uint16](prg.ram[index]) shl 8)

proc cycle(prg: Chip8Program): void =
  let pos = prg.stack[prg.stackPosition]
  var 
    instructionMask = prg.ram[pos] shr 4
    instruction = prg.getInstruction(pos)
  Chip8InstructionPointers[instructionMask](prg, instruction)
  prg.stack[prg.stackPosition] += InstructionSize

when isMainModule:
  var program = Chip8Program()
  program.ram[0] = 0x30
  program.ram[1] = 0x01
  program.cycle()