const std = @import("std");
const vm = @import("stack_vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const program = [_]vm.Instruction{
	// START CODING HERE REMOVE CODE IN THE PROGRAM CONST IF NEEDED
	// TO START CODING AND ADDING YOUR OWN STUFF
        // 10 + 32 = 42
        vm.makeInst2(.PUSH, 10, 0),    // Push 10
        vm.makeInst2(.PUSH, 32, 0),    // Push 32
        vm.makeInst(.ADD),             // Add them (10 + 32 = 42)
        vm.makeInst(.PRINT),           // Print result: 42
        
        vm.makeInst2(.PUSH, 100, 0),   // Push 100
        vm.makeInst1(.STORE_GLOBAL, 0), // Store in global variable 0
        vm.makeInst1(.LOAD_GLOBAL, 0), // Load it back
        vm.makeInst(.PRINT),           // Print: 100
        
        vm.makeInst(.HALT),            // Stop execution
    };
    
    var virtm = try vm.VM.init(allocator, &program);
    defer virtm.deinit();
    
    try virtm.execute();
    virtm.printMemoryStats();
}