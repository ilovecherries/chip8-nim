import sugar

const
  DisplayX = 64
  DisplayY = 32
  VramSize = DisplayY
  RamSize = 0xFFF - 0x200
  StackSize = 0x16
  VariablesSize = 0x10
  KeyboardSize = 0x10

type
  Chip8Program = ref object
    vram: array[VramSize, uint64]
    ram: array[RamSize, byte]
    stack: array[StackSize, uint32]
    stackPosition: uint8
    vars: array[VariablesSize, uint8]
    keyboard: array[KeyboardSize, uint8]

var Chip8InstructionPointers: array[0x10, ((Chip8Program, var uint16) -> void)]

template chip8Instruction(mask: SomeInteger, name: untyped, prg: untyped, ins: untyped, body: untyped) =
  proc name(prg: Chip8Program, ins: var uint16): void =
    body
  Chip8InstructionPointers[mask] = name

chip8Instruction(0, systemCall, prg, ins):
  type SystemCalls = enum
    CLS = 0x00E0, RET = 0x00EE
  case SystemCalls(ins and 0xFF):
    of SystemCalls.CLS: 
      echo "CLEAR MEMORY"
    of SystemCalls.RET:
      echo "RETURN FROM POSITION"

chip8Instruction(1, jumpCall, prg, ins):
  inc prg.stackPosition
  assert prg.stackPosition <= StackSize, "The stack pointer has been increased too many times!"
  prg.stack[prg.stackPosition] = ins and 0x0FFF
  echo "JUMPED TO ", ins and 0x0FFF

proc getInstruction(prg: Chip8Program, index: uint32): uint16 =
  return (cast[uint16](prg.ram[index+1]) shl 0) or 
         (cast[uint16](prg.ram[index]) shl 8)

proc cycle(prg: Chip8Program): void =
  let pos = prg.stack[prg.stackPosition]
  var 
    instructionMask = prg.ram[pos] shr 4
    instruction = prg.getInstruction(pos)
  Chip8InstructionPointers[instructionMask](prg, instruction)
  inc prg.stack[prg.stackPosition]

when isMainModule:
  var program = Chip8Program()
  program.ram[0] = 0x1E
  program.ram[1] = 0xE0
  program.cycle()