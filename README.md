# VM

A simple stack-based virtual machine (VM) written in Zig that runs bytecode.

## How It Works

The VM stores values in a stack, runs operations on them, and removes the results.

```
Example: Calculate 5 + 3

Step 1: PUSH 5          Step 2: PUSH 3          Step 3: ADD
┌─────────┐            ┌─────────┐            ┌─────────┐
│         │            │    3    │            │    8    │ ← Result
│         │            │    5    │            │         │
│    5    │            │         │            │         │
└─────────┘            └─────────┘            └─────────┘
   SP=1                   SP=2                   SP=1

ADD pops 3 and 5, adds them (5+3=8), and pushes 8 back
```

The VM includes:
- **Stack**: Stores values during calculations
- **Instructions**: Commands like PUSH, ADD, or PRINT
- **Memory**: Holds variables
- **Garbage Collector**: Cleans up unused memory

## Using the VM

### 1. Write Instructions
Define a program with instructions in `main.zig` in the main function:
```zig
const program = [_]vm.Instruction{
    vm.makeInst2(.PUSH, 42, 0),  // Push number 42
    vm.makeInst(.PRINT),         // Print it
    vm.makeInst(.HALT),          // Stop
};
```

### 2. Run the VM
Initialize and execute the VM:
```zig
var virtm = try vm.VM.init(allocator, &program);
defer virtm.deinit();
try virtm.execute();  // Outputs: 42
```

## Key Instructions

### Stack Operations
- **PUSH**: Add a value (e.g., `vm.makeInst2(.PUSH, 42, 0)` pushes integer 42)
- **POP**: Remove the top value
- **DUP**: Copy the top value
- **SWAP**: Swap the top two values

### Math Operations
- **ADD**: Add two values
- **SUB**: Subtract (a - b)
- **MUL**: Multiply
- **DIV**: Divide (errors on divide by zero)
- **MOD**: Get remainder (integers only)
- **NEG**: Negate a value

### Comparisons
- **EQ**: Check if equal
- **NE**: Check if not equal
- **LT**: Less than
- **LE**: Less than or equal
- **GT**: Greater than
- **GE**: Greater than or equal

### Logic Operations
- **AND**: True if both values are truthy
- **OR**: True if either value is truthy
- **NOT**: Flip true to false or vice versa

### Variables
- **STORE_GLOBAL**: Save to global variable (e.g., `vm.makeInst1(.STORE_GLOBAL, 0)`)
- **LOAD_GLOBAL**: Load from global variable
- **STORE_VAR**: Save to local variable
- **LOAD_VAR**: Load from local variable

### Control Flow
- **JUMP**: Go to an instruction
- **JUMP_IF_FALSE**: Jump if top value is false
- **JUMP_IF_TRUE**: Jump if top value is true

### Loops
- **FOR_INIT**: Start a for loop
- **FOR_CONDITION**: Check loop condition
- **FOR_INCREMENT**: Update loop counter
- **FOR_END**: End for loop
- **WHILE_START**: Start a while loop
- **WHILE_CONDITION**: Check while condition
- **WHILE_END**: End while loop
- **BREAK**: Exit a loop
- **CONTINUE**: Skip to next loop iteration

### Arrays
- **ARRAY_NEW**: Create an empty array
- **ARRAY_GET**: Get value at index
- **ARRAY_SET**: Set value at index
- **ARRAY_LEN**: Get array length
- **ARRAY_PUSH**: Add value to end
- **ARRAY_POP**: Remove and return last value

### Other Features
- **PRINT**: Print the top value
- **INPUT**: Read a line from input
- **HALT**: Stop the program
- **GC_COLLECT**: Run garbage collection

## Examples

### Math
```zig
const program = [_]vm.Instruction{
    vm.makeInst2(.PUSH, 10, 0),  // Push 10
    vm.makeInst2(.PUSH, 5, 0),   // Push 5
    vm.makeInst(.ADD),           // Add (10 + 5 = 15)
    vm.makeInst(.PRINT),         // Print 15
    vm.makeInst(.HALT),          // Stop
};
```

### Using Variables
```zig
const program = [_]vm.Instruction{
    vm.makeInst2(.PUSH, 42, 0),      // Push 42
    vm.makeInst1(.STORE_GLOBAL, 0),  // Save to global variable 0
    vm.makeInst1(.LOAD_GLOBAL, 0),   // Load from global variable 0
    vm.makeInst(.PRINT),             // Print 42
    vm.makeInst(.HALT),              // Stop
};
```

### Loop
```zig
const program = [_]vm.Instruction{
    vm.makeInst2(.PUSH, 0, 0),         // Push counter = 0
    vm.makeInst1(.STORE_GLOBAL, 0),    // Save to global variable 0
    vm.makeInst1(.LOAD_GLOBAL, 0),     // Load counter
    vm.makeInst(.DUP),                 // Copy counter
    vm.makeInst2(.PUSH, 5, 0),         // Push 5
    vm.makeInst(.LT),                  // Check if counter < 5
    vm.makeInst1(.JUMP_IF_FALSE, 12),  // Exit loop if false
    vm.makeInst1(.LOAD_GLOBAL, 0),     // Load counter
    vm.makeInst(.PRINT),               // Print counter
    vm.makeInst1(.LOAD_GLOBAL, 0),     // Load counter
    vm.makeInst2(.PUSH, 1, 0),         // Push 1
    vm.makeInst(.ADD),                 // Add 1 to counter
    vm.makeInst1(.STORE_GLOBAL, 0),    // Save new counter
    vm.makeInst1(.JUMP, 2),            // Jump to loop start
    vm.makeInst(.HALT),                // Stop
};
// Prints: 0 1 2 3 4
```

## Running it
To build and run:
```bash
zig run main.zig
```

