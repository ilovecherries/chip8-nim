import algorithm, sugar, random

type
  DelayTimer = uint8

const
  DisplayX* = 64
  DisplayY* = 32
  RamSize = 0xFFFF
  StackSize = 0x16
  VariablesSize = 0x10
  KeyboardSize = 0x10
  DelayTimerLength = cast[DelayTimer](60)
  ## Amount of ticks that the delay timer resets to
  InstructionSize = 2 # bytes
  ## The size of an instruction in bytes.
  DigitSpriteSize = 5
  ## The amount of bytes in memory that a digit sprite takes.
  DigitSpriteData = [ 
    0xF0, 0x90, 0x90, 0x90, 0xF0, # 0
    0x20, 0x60, 0x20, 0x20, 0x70, # 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
    0x90, 0x90, 0xF0, 0x10, 0x10, # 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
    0xF0, 0x10, 0x20, 0x40, 0x40, # 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, # A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
    0xF0, 0x80, 0x80, 0x80, 0xF0, # C
    0xE0, 0x90, 0x90, 0x90, 0xE0, # D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
    0xF0, 0x80, 0xF0, 0x80, 0x80  # F 
  ]

type
  Chip8* = ref object
    vram*: array[DisplayY, array[DisplayX, uint8]]
    ram*: array[RamSize, byte]
    stack*: array[StackSize, uint32]
    stackPosition*: uint8
    vars: array[VariablesSize, uint8]
    keyboard*: array[KeyboardSize, bool]
    i: uint16
    ## A special 16-bit register for storing memory addresses for operations. 
    endPoint*: uint32
    dt*: DelayTimer
    ## Delay timer that increments at the rate of HZ.
    st: uint8
    ## Sound timer. As long as `st` is larger than 0, play a noise.

proc tick*(dt: var DelayTimer) =
  dt = if dt == 0: DelayTimerLength else: dt - 1

proc initializeDigits(prg: Chip8): void =
  ## Initializes the CHIP8 ROM memory to contain the digits.
  for i in DigitSpriteData.low..<DigitSpriteData.high:
    prg.ram[i] = cast[uint8](DigitSpriteData[i])
  return

proc newChip8*(): Chip8 =
  var chip8 = Chip8()
  chip8.initializeDigits()
  return chip8

var Chip8InstructionPointers: array[0x10, ((Chip8, var uint16) -> void)]

template chip8Instruction(mask: SomeInteger, prg: untyped,
                          ins: untyped, body: untyped) =
  Chip8InstructionPointers[mask] = proc (prg: Chip8,
                                         ins: var uint16): void =
    body

proc getNibble(prg: Chip8, i: SomeInteger): byte =
  return prg.ram[(i div 2)] shr (4 * cast[int](i mod 2 == 0)) and 0xF

proc getInstruction(prg: Chip8, i: SomeInteger): uint16 =
  return (cast[uint16](prg.ram[i]) shl 8) or cast[uint16](prg.ram[i+1])

chip8Instruction(0, prg, ins):
  case cast[byte](ins and 0xFF):
    # 00E0 - CLS
    # Clear the display.
    of 0x00E0: 
      for i in countup(0, prg.vram.len - 1):
        prg.vram[i].fill(0)
    # 00EE - RET
    # Return from a subroutine.
    # The interpreter sets the program counter to the address at the top of
    # the stack, then subtracts 1 from the stack pointer.
    of 0x00EE:
      dec prg.stackPosition
      assert prg.stackPosition >= 0,
       "The stack position has been decreased too many times!"
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
# The interpreter increments the stack pointer, then puts the current PC on the
# top of the stack. The PC is then set to nnn.
chip8Instruction(2, prg, ins):
  inc prg.stackPosition
  assert prg.stackPosition <= StackSize,
      "The stack pointer has been increased too many times!"
  prg.stack[prg.stackPosition] = (ins and 0x0FFF) - InstructionSize

# 3xkk - SE Vx, byte
# Skip next instruction if Vx = kk.
# The interpreter compares register Vx to kk, and if they are equal, increments
# the program counter by 2.
chip8Instruction(3, prg, ins):
  let
    variable = ins shr 8 and 0xF
    value = ins and 0xFF
  if prg.vars[variable] == value:
    prg.stack[prg.stackPosition] += InstructionSize

# 4xkk - SNE Vx, byte
# Skip next instruction if Vx != kk.
# The interpreter compares register Vx to kk, and if they are not equal,
# increments the program counter by 2.
chip8Instruction(4, prg, ins):
  let
    variable = prg.vars[ins shr 8 and 0xF]
    value = ins and 0xFF
  if variable != value:
    prg.stack[prg.stackPosition] += InstructionSize

# 5xy0 - SE Vx, Vy
# Skip next instruction if Vx = Vy.
# The interpreter compares register Vx to register Vy, and if they are equal,
# increments the program counter by 2.
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
    LD, OR, AND, XOR, ADD, SUB, SHR, SUBN, SHL = 14
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
    # Performs a bitwise exclusive OR on the values of Vx and Vy, then stores
    # the result in Vx.
    of VariableOperations.XOR:
      prg.vars[variableX] = prg.vars[variableX] xor prg.vars[variableY]
    # 8xy4 - ADD Vx, Vy
    # Set Vx = Vx + Vy, set VF = carry.
    # The values of Vx and Vy are added together. If the result is greater than
    # 8 bits (i.e., > 255,) VF is set to 1, otherwise 0. Only the lowest 8 bits
    # of the result are kept, and stored in Vx.
    of VariableOperations.ADD:
      let res = cast[int16](prg.vars[variableX] + prg.vars[variableY])
      prg.vars[0xF] = if res > 255: 1 else: 0
      prg.vars[variableX] = cast[uint8](res and 0xFF)
    # 8xy5 - SUB Vx, Vy
    # Set Vx = Vx - Vy, set VF = NOT borrow.
    # If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is subtracted from
    # Vx, and the results stored in Vx.
    of VariableOperations.SUB:
      prg.vars[0xF] = if prg.vars[variableX] > prg.vars[variableY]: 1 else: 0
      prg.vars[variableX] = prg.vars[variableX] - prg.vars[variableY]
    # 8xy6 - SHR Vx {, Vy}
    # Set Vx = Vx SHR 1.
    # If the least-significant bit of Vx is 1, then VF is set to 1, otherwise 0. 
    # Then Vx is divided by 2.
    of VariableOperations.SHR:
      prg.vars[0xF] = prg.vars[variableX] and 1
      prg.vars[variableX] = (prg.vars[variableX]) div 2
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
      prg.vars[variableX] = (prg.vars[variableX]) * 2

# 9xy0 - SNE Vx, Vy
# Skip next instruction if Vx != Vy.
# The values of Vx and Vy are compared, and if they are not equal,
# the program counter is increased by 2.
chip8Instruction(9, prg, ins):
  let 
    variableX = ins shr 8 and 0xF
    variableY = ins shr 4 and 0xF
  if prg.vars[variableX] != prg.vars[variableY]:
    prg.stack[prg.stackPosition] += InstructionSize

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
  prg.vars[0xF] = 0
  # iterate through all bytes
  for i in cast[uint64](0)..<n:
    let vramPositionY = (y + i) mod DisplayY
    for j in countdown(7, 0) :
      let 
        bit = (prg.ram[prg.i + i] shr j) and 1
        vramPositionX = (56 - x + cast[uint8](j)) mod DisplayX
      let
        collision = (prg.vram[vramPositionY][vramPositionX] and 1) and bit
      prg.vars[0xF] = prg.vars[0xF] or cast[uint8](collision)
      prg.vram[vramPositionY][vramPositionX] =
          prg.vram[vramPositionY][vramPositionX] xor bit
  
chip8Instruction(0xE, prg, ins):
  type KeyboardInstructions = enum
    Down = 0x9E, Up = 0xA1
  let
    variable = ins shr 8 and 0xF
    instruction = ins and 0xFF
  case KeyboardInstructions(instruction):
    # Ex9E - SKP Vx
    # Skip next instruction if key with the value of Vx is pressed.
    # Checks the keyboard, and if the key corresponding to the value of Vx 
    # is currently in the down position, PC is increased by 2.
    of KeyboardInstructions.Down:
      if prg.keyboard[prg.vars[variable]]:
        prg.stack[prg.stackPosition] += InstructionSize
    # ExA1 - SKNP Vx
    # Skip next instruction if key with the value of Vx is not pressed.
    # Checks the keyboard, and if the key corresponding to the value of 
    # Vx is currently in the up position, PC is increased by 2.
    of KeyboardInstructions.Up:
      if not prg.keyboard[prg.vars[variable]]:
        prg.stack[prg.stackPosition] += InstructionSize

chip8Instruction(0xF, prg, ins):
  let
    variable = ins shr 8 and 0xF
    instruction = ins and 0xFF
  case instruction:
    # Fx07 - LD Vx, DT
    # Set Vx = delay timer value.
    # The value of DT is placed into Vx.
    of 0x07:
      prg.vars[variable] = prg.dt
    # Fx0A - LD Vx, K
    # Wait for a key press, store the value of the key in Vx.
    # All execution stops until a key is pressed, then the 
    # value of that key is stored in Vx.
    of 0x0A:
      # TODO: NEED TO IMPLEMENT KEYBOARD, THIS IS PLACEHOLDER UNTIL THEN
      prg.vars[variable] = 0
    # Fx15 - LD DT, Vx
    # Set delay timer = Vx.
    # DT is set equal to the value of Vx.
    of 0x15:
      prg.dt = prg.vars[variable]
    # Fx18 - LD ST, Vx
    # Set sound timer = Vx.
    # ST is set equal to the value of Vx.
    of 0x18:
      prg.st = prg.vars[variable]
    # Fx1E - ADD I, Vx
    # Set I = I + Vx.
    # The values of I and Vx are added, and the 
    # results are stored in I.
    of 0x1E:
      prg.i += prg.vars[variable]
    # Fx29 - LD F, Vx
    # Set I = location of sprite for digit Vx.
    # The value of I is set to the location for the 
    # hexadecimal sprite corresponding to the value of Vx.
    of 0x29:
      prg.i = prg.vars[variable] * DigitSpriteSize
    # Fx33 - LD B, Vx
    # Store BCD representation of Vx in memory locations I, I+1, and I+2.
    # The interpreter takes the decimal value of Vx, and places the hundreds 
    # digit in memory at location in I, the tens digit at location I+1, and 
    # the ones digit at location I+2.
    of 0x33:
      prg.ram[prg.i] = (prg.vars[variable] div 100) mod 10
      prg.ram[prg.i+1] = (prg.vars[variable] div 10) mod 10
      prg.ram[prg.i+2] = prg.vars[variable] mod 10
    # Fx55 - LD [I], Vx
    # Store registers V0 through Vx in memory starting at location I.
    # The interpreter copies the values of registers V0 through Vx into 
    # memory, starting at the address in I.
    of 0x55:
      for i in cast[uint64](0)..variable:
        prg.ram[prg.i + i] = prg.vars[i]
    # Fx65 - LD Vx, [I]
    # Read registers V0 through Vx from memory starting at location I.
    # The interpreter reads values from memory starting at location I into 
    # registers V0 through Vx.
    of 0x65:
      for i in cast[uint64](0)..variable:
        prg.vars[i] = prg.ram[prg.i + i]
    else:
      return
  return

proc cycle*(prg: Chip8): void =
  let pos = prg.stack[prg.stackPosition]
  var 
    instructionMask = prg.getNibble(pos * InstructionSize)
    instruction = prg.getInstruction(pos)
  Chip8InstructionPointers[instructionMask](prg, instruction)
  prg.stack[prg.stackPosition] += InstructionSize
