const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const LoopType = enum { for_loop, while_loop };

const ValueType = enum { nil, int, float, string, bool, array, hashmap, struct_val, function, closure };

const Value = union(ValueType) {
    nil: void,
    int: i64,
    float: f64,
    string: []const u8,
    bool: bool,
    array: *Array,
    hashmap: *HashMap,
    struct_val: *Struct,
    function: *Function,
    closure: *Closure,

    pub fn toString(self: Value, allocator: Allocator) ![]const u8 {
        return switch (self) {
            .nil => "nil",
            .int => try std.fmt.allocPrint(allocator, "{}", .{self.int}),
            .float => try std.fmt.allocPrint(allocator, "{}", .{self.float}),
            .string => self.string,
            .bool => if (self.bool) "true" else "false",
            .array => try std.fmt.allocPrint(allocator, "Array[{}]", .{self.array.items.items.len}),
            .hashmap => try std.fmt.allocPrint(allocator, "HashMap[{}]", .{self.hashmap.map.count()}),
            .struct_val => try std.fmt.allocPrint(allocator, "Struct[{}]", .{self.struct_val.fields.count()}),
            .function => try std.fmt.allocPrint(allocator, "Function@{}", .{self.function.address}),
            .closure => try std.fmt.allocPrint(allocator, "Closure@{}", .{self.closure.function.address}),
        };
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .nil => false,
            .bool => self.bool,
            .int => self.int != 0,
            .float => self.float != 0.0,
            .string => self.string.len > 0,
            .array => self.array.items.items.len > 0,
            .hashmap => self.hashmap.map.count() > 0,
            .struct_val => true,
            .function => true,
            .closure => true,
        };
    }
};

const Array = struct {
    items: std.ArrayList(Value),

    pub fn init(allocator: Allocator) Array {
        return Array{ .items = std.ArrayList(Value).init(allocator) };
    }

    pub fn deinit(self: *Array) void {
        self.items.deinit();
    }
};

const HashMap = struct {
    map: std.AutoHashMap(u64, Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator) HashMap {
        return HashMap{
            .map = std.AutoHashMap(u64, Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HashMap) void {
        self.map.deinit();
    }

    fn hashString(str: []const u8) u64 {
        return std.hash_map.hashString(str);
    }
};

const Struct = struct {
    fields: std.AutoHashMap(u64, Value),

    pub fn init(allocator: Allocator) Struct {
        return Struct{
            .fields = std.AutoHashMap(u64, Value).init(allocator),
        };
    }

    pub fn deinit(self: *Struct) void {
        self.fields.deinit();
    }
};

const Function = struct {
    address: usize,
    arity: usize,
    name: []const u8,
    is_varargs: bool,
    local_count: usize,
};

const Closure = struct {
    function: *Function,
    captures: std.ArrayList(Value),

    pub fn init(allocator: Allocator, function: *Function) Closure {
        return Closure{
            .function = function,
            .captures = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Closure) void {
        self.captures.deinit();
    }
};

const OpCode = enum(u8) {
    PUSH,
    POP,
    DUP,
    SWAP,
    ADD,
    SUB,
    MUL,
    DIV,
    MOD,
    NEG,
    EQ,
    NE,
    LT,
    LE,
    GT,
    GE,
    AND,
    OR,
    NOT,
    LOAD_VAR,
    STORE_VAR,
    LOAD_GLOBAL,
    STORE_GLOBAL,
    JUMP,
    JUMP_IF_FALSE,
    JUMP_IF_TRUE,
    CALL,
    RETURN,
    LOAD_ARG,
    STORE_ARG,
    FOR_INIT,
    FOR_CONDITION,
    FOR_INCREMENT,
    FOR_END,
    WHILE_START,
    WHILE_CONDITION,
    WHILE_END,
    BREAK,
    CONTINUE,
    SWITCH_START,
    CASE,
    DEFAULT_CASE,
    SWITCH_END,
    TRY_START,
    CATCH,
    THROW,
    TRY_END,
    ARRAY_NEW,
    ARRAY_GET,
    ARRAY_SET,
    ARRAY_LEN,
    ARRAY_PUSH,
    ARRAY_POP,
    HASHMAP_NEW,
    HASHMAP_GET,
    HASHMAP_SET,
    HASHMAP_HAS,
    HASHMAP_DELETE,
    STRUCT_NEW,
    STRUCT_GET,
    STRUCT_SET,
    FUNCTION_DEF,
    CLOSURE_NEW,
    CLOSURE_CAPTURE,
    STRING_CONCAT,
    STRING_SUBSTR,
    STRING_LEN,
    STRING_COMPARE,
    PRINT,
    INPUT,
    GC_COLLECT,
    WEAK_REF_NEW,
    WEAK_REF_GET,
    HALT,
    NOP,
};

pub const Instruction = struct {
    opcode: OpCode,
    operand: i32 = 0,
    operand2: i32 = 0,
    operand3: i32 = 0,
    debug_info: ?DebugInfo = null,
};

const DebugInfo = struct {
    line: u32,
    column: u32,
    file: []const u8,
};

const CallFrame = struct {
    return_addr: usize,
    base_ptr: usize,
    arg_count: usize,
    is_exception_handler: bool = false,
    catch_addr: usize = 0,
};

const LoopFrame = struct {
    start_addr: usize,
    end_addr: usize,
    loop_type: LoopType,
    counter_var: ?usize = null,
};

const Exception = struct {
    message: []const u8,
    stack_trace: std.ArrayList(DebugInfo),

    pub fn init(allocator: Allocator, message: []const u8) Exception {
        return Exception{
            .message = message,
            .stack_trace = std.ArrayList(DebugInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Exception) void {
        self.stack_trace.deinit();
    }
};

const SwitchFrame = struct {
    cases: std.ArrayList(SwitchCase),
    default_addr: ?usize,
    end_addr: usize,

    pub fn init(allocator: Allocator, end_addr: usize) SwitchFrame {
        return SwitchFrame{
            .cases = std.ArrayList(SwitchCase).init(allocator),
            .default_addr = null,
            .end_addr = end_addr,
        };
    }

    pub fn deinit(self: *SwitchFrame) void {
        self.cases.deinit();
    }
};

const SwitchCase = struct {
    value: Value,
    addr: usize,
};

const WeakRef = struct {
    target: ?*GCObj,

    pub fn get(self: *WeakRef) ?Value {
        if (self.target) |obj| {
            if (obj.refs > 0) return obj.value;
        }
        return null;
    }
};

const VMError = error{
    StackUnderflow,
    StackOverflow,
    InvalidInstruction,
    DivisionByZero,
    TypeError,
    UndefinedVariable,
    OutOfMemory,
    InvalidJump,
    InputOutput,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    ProcessNotFound,
    Unexpected,
    EndOfStream,
    IsDir,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    Canceled,
    StreamTooLong,
    IndexOutOfBounds,
    KeyNotFound,
    InvalidOperation,
    RuntimeException,
    BreakOutsideLoop,
    ContinueOutsideLoop,
    InvalidCast,
};

const GCObj = struct {
    marked: bool = false,
    generation: u8 = 0,
    value: Value,
    refs: usize = 1,
    weak_refs: std.ArrayList(*WeakRef),

    pub fn init(allocator: Allocator, value: Value) GCObj {
        return GCObj{
            .value = value,
            .weak_refs = std.ArrayList(*WeakRef).init(allocator),
        };
    }

    pub fn deinit(self: *GCObj, vm_allocator: Allocator) void {

        for (self.weak_refs.items) |weak_ref| {
            weak_ref.target = null;
        }
        self.weak_refs.deinit();

        switch (self.value) {
            .array => |arr| {
                arr.deinit();
                vm_allocator.destroy(arr); 
            },
            .hashmap => |hm| {
                hm.deinit();
                vm_allocator.destroy(hm); 
            },
            .struct_val => |s| {
                s.deinit();
                vm_allocator.destroy(s); 
            },
            .closure => |c| {
                c.deinit();
                vm_allocator.destroy(c); 
            },
            .function => |f| {
                vm_allocator.destroy(f); 
            },
            else => {},
        }
    }

    pub fn mark(self: *GCObj, gc: *GenerationalGC) void {
        if (!self.marked) {
            self.marked = true;
            switch (self.value) {
                .array => |arr| {
                    for (arr.items.items) |item| {
                        gc.markValue(item);
                    }
                },
                .hashmap => |hm| {
                    var iterator = hm.map.iterator();
                    while (iterator.next()) |entry| {
                        gc.markValue(entry.value_ptr.*);
                    }
                },
                .struct_val => |s| {
                    var iterator = s.fields.iterator();
                    while (iterator.next()) |entry| {
                        gc.markValue(entry.value_ptr.*);
                    }
                },
                .closure => |c| {
                    for (c.captures.items) |capture| {
                        gc.markValue(capture);
                    }
                },
                else => {},
            }
        }
    }

    fn markValue(self: *GenerationalGC, value: Value) void {
		// my least favorite function of the whole project
		// beacuse this shit caused me so many issues and i hate it!
		// burrp
        switch (value) {
            .array => |arr| {

                for (self.young_gen.items) |obj| {
                    if (obj.value == .array and obj.value.array == arr) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .array and obj.value.array == arr) {
                        obj.mark(self);
                        return;
                    }
                }
            },
            .hashmap => |hm| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .hashmap and obj.value.hashmap == hm) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .hashmap and obj.value.hashmap == hm) {
                        obj.mark(self);
                        return;
                    }
                }
            },
            .struct_val => |s| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .struct_val and obj.value.struct_val == s) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .struct_val and obj.value.struct_val == s) {
                        obj.mark(self);
                        return;
                    }
                }
            },
            .closure => |c| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .closure and obj.value.closure == c) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .closure and obj.value.closure == c) {
                        obj.mark(self);
                        return;
                    }
                }
            },
            .function => |f| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .function and obj.value.function == f) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .function and obj.value.function == f) {
                        obj.mark(self);
                        return;
                    }
                }
            },
            else => {},
        }
    }
};

const GenerationalGC = struct {
    young_gen: std.ArrayList(*GCObj),
    old_gen: std.ArrayList(*GCObj),
    allocator: Allocator,
    collection_count: usize = 0,
    young_threshold: usize = 100,
    old_threshold: usize = 1000,

    pub fn init(allocator: Allocator) GenerationalGC {
        return GenerationalGC{
            .young_gen = std.ArrayList(*GCObj).init(allocator),
            .old_gen = std.ArrayList(*GCObj).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GenerationalGC) void {
        self.collectAll();
        self.young_gen.deinit();
        self.old_gen.deinit();
    }

    pub fn allocate(self: *GenerationalGC, value: Value) !*GCObj {
        const obj = try self.allocator.create(GCObj);
        obj.* = GCObj.init(self.allocator, value);
        try self.young_gen.append(obj);

        if (self.young_gen.items.len > self.young_threshold) {
            try self.collectYoung();
        }

        return obj;
    }

    fn markRoots(self: *GenerationalGC, vm: *VM) void {
        for (vm.stack[0..vm.sp]) |value| {
            self.markValue(value);
        }

        for (vm.globals) |value| {
            if (value != .nil) {
                self.markValue(value);
            }
        }

        for (vm.call_stack[0..vm.call_sp]) |frame| {
            const end_idx = @min(frame.base_ptr + frame.arg_count, vm.sp);
            for (vm.stack[frame.base_ptr..end_idx]) |value| {
                self.markValue(value);
            }
        }
    }

    fn markValue(self: *GenerationalGC, value: Value) void {
        switch (value) {
            .array => |arr| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .array and obj.value.array == arr) {
                        obj.mark(self); 
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .array and obj.value.array == arr) {
                        obj.mark(self); 
                        return;
                    }
                }
            },
            .hashmap => |hm| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .hashmap and obj.value.hashmap == hm) {
                        obj.mark(self); 
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .hashmap and obj.value.hashmap == hm) {
                        obj.mark(self); 
                        return;
                    }
                }
            },
            .struct_val => |s| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .struct_val and obj.value.struct_val == s) {
                        obj.mark(self); 
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .struct_val and obj.value.struct_val == s) {
                        obj.mark(self); 
                        return;
                    }
                }
            },
            .closure => |c| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .closure and obj.value.closure == c) {
                        obj.mark(self); 
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .closure and obj.value.closure == c) {
                        obj.mark(self); 
                        return;
                    }
                }
            },
            .function => |f| {
                for (self.young_gen.items) |obj| {
                    if (obj.value == .function and obj.value.function == f) {
                        obj.mark(self);
                        return;
                    }
                }
                for (self.old_gen.items) |obj| {
                    if (obj.value == .function and obj.value.function == f) {
                        obj.mark(self); 
                        return;
                    }
                }
            },
            else => {},
        }
    }

    fn collectYoung(self: *GenerationalGC) !void {
        var i: usize = 0;
        while (i < self.young_gen.items.len) {
            const obj = self.young_gen.items[i];
            if (!obj.marked) {
                obj.deinit(self.allocator);
                self.allocator.destroy(obj);
                _ = self.young_gen.swapRemove(i);
            } else {
                obj.generation += 1;
                if (obj.generation > 3) {
                    try self.old_gen.append(obj);
                    _ = self.young_gen.swapRemove(i);
                } else {
                    obj.marked = false;
                    i += 1;
                }
            }
        }
    }

    fn collectOld(self: *GenerationalGC) void {
        var i: usize = 0;
        while (i < self.old_gen.items.len) {
            const obj = self.old_gen.items[i];
            if (!obj.marked) {
                obj.deinit(self.allocator);
                self.allocator.destroy(obj);
                _ = self.old_gen.swapRemove(i);
            } else {
                obj.marked = false;
                i += 1;
            }
        }
    }

    fn collectAll(self: *GenerationalGC) void {
        for (self.young_gen.items) |obj| {
            obj.deinit(self.allocator);
            self.allocator.destroy(obj);
        }
        for (self.old_gen.items) |obj| {
            obj.deinit(self.allocator);
            self.allocator.destroy(obj);
        }
        self.young_gen.clearAndFree();
        self.old_gen.clearAndFree();
    }

    pub fn fullCollect(self: *GenerationalGC, vm: *VM) !void {
        self.markRoots(vm);
        try self.collectYoung();
        self.collectOld();
        self.collection_count += 1;
    }
};

pub const VM = struct {
    const STACK_SIZE = 8192;
    const CALL_STACK_SIZE = 1024;
    const LOOP_STACK_SIZE = 256;
    const SWITCH_STACK_SIZE = 128;
    const GLOBAL_VAR_COUNT = 1024;

    allocator: Allocator,
    stack: [STACK_SIZE]Value,
    sp: usize,
    ip: usize,
    bp: usize,
    program: []const Instruction,

    call_stack: [CALL_STACK_SIZE]CallFrame,
    call_sp: usize,

    loop_stack: [LOOP_STACK_SIZE]LoopFrame,
    loop_sp: usize,

    switch_stack: [SWITCH_STACK_SIZE]SwitchFrame,
    switch_sp: usize,

    globals: [GLOBAL_VAR_COUNT]Value,

    gc: GenerationalGC,

    current_exception: ?Exception,

    functions: std.AutoHashMap(u64, Function),

    weak_refs: std.ArrayList(*WeakRef),

    pub fn init(allocator: Allocator, program: []const Instruction) !VM {
        var vm = VM{
            .allocator = allocator,
            .stack = undefined,
            .sp = 0,
            .ip = 0,
            .bp = 0,
            .program = program,
            .call_stack = undefined,
            .call_sp = 0,
            .loop_stack = undefined,
            .loop_sp = 0,
            .switch_stack = undefined,
            .switch_sp = 0,
            .globals = undefined,
            .gc = GenerationalGC.init(allocator),
            .current_exception = null,
            .functions = std.AutoHashMap(u64, Function).init(allocator),
            .weak_refs = std.ArrayList(*WeakRef).init(allocator),
        };

        for (&vm.stack) |*val| val.* = Value.nil;
        for (&vm.globals) |*global| global.* = Value.nil;

        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.gc.deinit();
        self.functions.deinit();
        for (self.weak_refs.items) |weak_ref| {
            self.allocator.destroy(weak_ref);
        }
        self.weak_refs.deinit();
        if (self.current_exception) |*ex| {
            ex.deinit();
        }
    }

    fn push(self: *VM, value: Value) VMError!void {
        if (self.sp >= STACK_SIZE) return VMError.StackOverflow;
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn pop(self: *VM) VMError!Value {
        if (self.sp == 0) return VMError.StackUnderflow;
        self.sp -= 1;
        return self.stack[self.sp];
    }

    fn peek(self: *VM, offset: usize) VMError!Value {
        if (self.sp <= offset) return VMError.StackUnderflow;
        return self.stack[self.sp - 1 - offset];
    }

    fn createArray(self: *VM) !Value {
        const arr = try self.allocator.create(Array);
        arr.* = Array.init(self.allocator);
        const gc_obj = try self.gc.allocate(Value{ .array = arr });
        return gc_obj.value;
    }

    fn arrayGet(self: *VM, arr: *Array, index: i64) VMError!Value {
        _ = self;
        if (index < 0 or index >= arr.items.items.len) {
            return VMError.IndexOutOfBounds;
        }
        return arr.items.items[@intCast(index)];
    }

    fn arraySet(self: *VM, arr: *Array, index: i64, value: Value) VMError!void {
        _ = self;
        if (index < 0) return VMError.IndexOutOfBounds;

        while (index >= arr.items.items.len) {
            try arr.items.append(Value.nil);
        }

        arr.items.items[@intCast(index)] = value;
    }

    fn createHashMap(self: *VM) !Value {
        const hm = try self.allocator.create(HashMap);
        hm.* = HashMap.init(self.allocator);
        const gc_obj = try self.gc.allocate(Value{ .hashmap = hm });
        return gc_obj.value;
    }

    fn createStruct(self: *VM) !Value {
        const s = try self.allocator.create(Struct);
        s.* = Struct.init(self.allocator);
        const gc_obj = try self.gc.allocate(Value{ .struct_val = s });
        return gc_obj.value;
    }

    fn stringConcat(self: *VM, a: []const u8, b: []const u8) ![]const u8 {
        const result = try self.allocator.alloc(u8, a.len + b.len);
        @memcpy(result[0..a.len], a);
        @memcpy(result[a.len..], b);
        return result;
    }

    fn stringSubstr(self: *VM, str: []const u8, start: i64, length: i64) ![]const u8 {
        if (start < 0 or start >= str.len) return VMError.IndexOutOfBounds;
        const end = @min(start + length, @as(i64, @intCast(str.len)));
        return try self.allocator.dupe(u8, str[@intCast(start)..@intCast(end)]);
    }

    fn throwException(self: *VM, message: []const u8) VMError!void {
        self.current_exception = Exception.init(self.allocator, message);

        while (self.call_sp > 0) {
            const frame = &self.call_stack[self.call_sp - 1];
            if (frame.is_exception_handler) {
                self.ip = frame.catch_addr;
                return;
            }
            self.call_sp -= 1;
            self.sp = frame.base_ptr;
            self.bp = frame.base_ptr;
        }

        return VMError.RuntimeException;
    }

    fn pushLoopFrame(self: *VM, start_addr: usize, end_addr: usize, loop_type: LoopType) VMError!void {
        if (self.loop_sp >= LOOP_STACK_SIZE) return VMError.StackOverflow;
        self.loop_stack[self.loop_sp] = LoopFrame{
            .start_addr = start_addr,
            .end_addr = end_addr,
            .loop_type = loop_type,
        };
        self.loop_sp += 1;
    }

    fn popLoopFrame(self: *VM) void {
        if (self.loop_sp > 0) self.loop_sp -= 1;
    }

    fn breakLoop(self: *VM) VMError!void {
        if (self.loop_sp == 0) return VMError.BreakOutsideLoop;
        const loop_frame = self.loop_stack[self.loop_sp - 1];
        self.ip = loop_frame.end_addr;
        self.popLoopFrame();
    }

    fn continueLoop(self: *VM) VMError!void {
        if (self.loop_sp == 0) return VMError.ContinueOutsideLoop;
        const loop_frame = self.loop_stack[self.loop_sp - 1];
        self.ip = loop_frame.start_addr;
    }

    fn createWeakRef(self: *VM, target: Value) !Value {
        const weak_ref = try self.allocator.create(WeakRef);

        var target_obj: ?*GCObj = null;
        for (self.gc.young_gen.items) |obj| {
            if (std.meta.eql(obj.value, target)) {
                target_obj = obj;
                break;
            }
        }
        if (target_obj == null) {
            for (self.gc.old_gen.items) |obj| {
                if (std.meta.eql(obj.value, target)) {
                    target_obj = obj;
                    break;
                }
            }
        }

        weak_ref.* = WeakRef{ .target = target_obj };

        if (target_obj) |obj| {
            try obj.weak_refs.append(weak_ref);
        }

        try self.weak_refs.append(weak_ref);
        return Value{ .int = @as(i64, @bitCast(@as(isize, @intCast(@intFromPtr(weak_ref))))) };
    }

    fn binaryOp(self: *VM, comptime op: anytype) VMError!void {
        const b = try self.pop();
        const a = try self.pop();
        var result: Value = undefined;

        switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| result = Value{ .int = op(ai, bi) },
                .float => |bf| result = Value{ .float = op(@as(f64, @floatFromInt(ai)), bf) },
                else => return VMError.TypeError,
            },
            .float => |af| switch (b) {
                .int => |bi| result = Value{ .float = op(af, @as(f64, @floatFromInt(bi))) },
                .float => |bf| result = Value{ .float = op(af, bf) },
                else => return VMError.TypeError,
            },
            else => return VMError.TypeError,
        }
        try self.push(result);
    }

    fn compareOp(self: *VM, comptime op: anytype) VMError!void {
        const b = try self.pop();
        const a = try self.pop();
        var result: bool = false;

        switch (a) {
            .int => |ai| switch (b) {
                .int => result = op(ai, b.int),
                .float => result = op(@as(f64, @floatFromInt(ai)), b.float),
                else => result = false,
            },
            .float => |af| switch (b) {
                .int => result = op(af, @as(f64, @floatFromInt(b.int))),
                .float => result = op(af, b.float),
                else => result = false,
            },
            .string => |as| switch (b) {
                .string => result = op(as.len, b.string.len),
                else => result = false,
            },
            .bool => |ab| switch (b) {
                .bool => |bb| {
                    const a_int: i32 = if (ab) 1 else 0;
                    const b_int: i32 = if (bb) 1 else 0;
                    result = op(a_int, b_int);
                },
                else => result = false,
            },
            else => result = false,
        }
        try self.push(Value{ .bool = result });
    }

    pub fn execute(self: *VM) VMError!void {
        while (self.ip < self.program.len) {
            const instruction = self.program[self.ip];

            switch (instruction.opcode) {
                .PUSH => {
                    const value = switch (instruction.operand2) {
                        0 => Value{ .int = instruction.operand },
                        1 => blk: {
                            const f: f64 = @floatFromInt(instruction.operand);
                            break :blk Value{ .float = f };
                        },
                        2 => Value{ .bool = instruction.operand != 0 },
                        3 => Value.nil,
                        else => Value{ .int = instruction.operand },
                    };
                    try self.push(value);
                },

                .POP => _ = try self.pop(),
                .DUP => try self.push(try self.peek(0)),
                .SWAP => {
                    const a = try self.pop();
                    const b = try self.pop();
                    try self.push(a);
                    try self.push(b);
                },

                .ADD => try self.binaryOp(struct {
                    fn f(a: anytype, b: anytype) @TypeOf(a) {
                        return a + b;
                    }
                }.f),
                .SUB => try self.binaryOp(struct {
                    fn f(a: anytype, b: anytype) @TypeOf(a) {
                        return a - b;
                    }
                }.f),
                .MUL => try self.binaryOp(struct {
                    fn f(a: anytype, b: anytype) @TypeOf(a) {
                        return a * b;
                    }
                }.f),
                .DIV => {
                    const divisor = try self.pop();
                    const dividend = try self.pop();
                    if ((divisor == .int and divisor.int == 0) or (divisor == .float and divisor.float == 0.0))
                        return VMError.DivisionByZero;
                    var result: Value = undefined;
                    switch (dividend) {
                        .int => |di| switch (divisor) {
                            .int => result = Value{ .int = @divTrunc(di, divisor.int) },
                            .float => result = Value{ .float = @as(f64, @floatFromInt(di)) / divisor.float },
                            else => return VMError.TypeError,
                        },
                        .float => |df| switch (divisor) {
                            .int => result = Value{ .float = df / @as(f64, @floatFromInt(divisor.int)) },
                            .float => result = Value{ .float = df / divisor.float },
                            else => return VMError.TypeError,
                        },
                        else => return VMError.TypeError,
                    }
                    try self.push(result);
                },
                .MOD => {
                    const b = try self.pop();
                    const a = try self.pop();
                    var result: Value = undefined;
                    switch (a) {
                        .int => |ai| switch (b) {
                            .int => |bi| {
                                if (bi == 0) return VMError.DivisionByZero;
                                result = Value{ .int = @mod(ai, bi) };
                            },
                            else => return VMError.TypeError,
                        },
                        else => return VMError.TypeError,
                    }
                    try self.push(result);
                },
                .NEG => {
                    const a = try self.pop();
                    var result: Value = undefined;
                    switch (a) {
                        .int => result = Value{ .int = -a.int },
                        .float => result = Value{ .float = -a.float },
                        else => return VMError.TypeError,
                    }
                    try self.push(result);
                },

                .EQ => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(Value{ .bool = std.meta.eql(a, b) });
                },
                .NE => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(Value{ .bool = !std.meta.eql(a, b) });
                },
                .LT => try self.compareOp(struct {
                    fn f(a: anytype, b: anytype) bool {
                        return a < b;
                    }
                }.f),
                .LE => try self.compareOp(struct {
                    fn f(a: anytype, b: anytype) bool {
                        return a <= b;
                    }
                }.f),
                .GT => try self.compareOp(struct {
                    fn f(a: anytype, b: anytype) bool {
                        return a > b;
                    }
                }.f),
                .GE => try self.compareOp(struct {
                    fn f(a: anytype, b: anytype) bool {
                        return a >= b;
                    }
                }.f),

                .AND => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(Value{ .bool = a.isTruthy() and b.isTruthy() });
                },
                .OR => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(Value{ .bool = a.isTruthy() or b.isTruthy() });
                },
                .NOT => {
                    const a = try self.pop();
                    try self.push(Value{ .bool = !a.isTruthy() });
                },

                .LOAD_VAR => {
                    const index = self.bp + @as(usize, @intCast(instruction.operand));
                    if (index >= self.sp) return VMError.UndefinedVariable;
                    try self.push(self.stack[index]);
                },
                .STORE_VAR => {
                    const value = try self.pop();
                    const index = self.bp + @as(usize, @intCast(instruction.operand));
                    if (index >= STACK_SIZE) return VMError.StackOverflow;
                    self.stack[index] = value;
                },
                .LOAD_GLOBAL => {
                    const index = @as(usize, @intCast(instruction.operand));
                    if (index >= GLOBAL_VAR_COUNT) return VMError.UndefinedVariable;
                    try self.push(self.globals[index]);
                },
                .STORE_GLOBAL => {
                    const value = try self.pop();
                    const index = @as(usize, @intCast(instruction.operand));
                    if (index >= GLOBAL_VAR_COUNT) return VMError.UndefinedVariable;
                    self.globals[index] = value;
                },

                .JUMP => {
                    const addr = @as(usize, @intCast(instruction.operand));
                    if (addr >= self.program.len) return VMError.InvalidJump;
                    self.ip = addr;
                    continue;
                },
                .JUMP_IF_FALSE => {
                    const condition = try self.pop();
                    if (!condition.isTruthy()) {
                        const addr = @as(usize, @intCast(instruction.operand));
                        if (addr >= self.program.len) return VMError.InvalidJump;
                        self.ip = addr;
                        continue;
                    }
                },
                .JUMP_IF_TRUE => {
                    const condition = try self.pop();
                    if (condition.isTruthy()) {
                        const addr = @as(usize, @intCast(instruction.operand));
                        if (addr >= self.program.len) return VMError.InvalidJump;
                        self.ip = addr;
                        continue;
                    }
                },

                .CALL => {
                    const arg_count = @as(usize, @intCast(instruction.operand));
                    const func_addr = @as(usize, @intCast(instruction.operand2));
                    if (self.call_sp >= CALL_STACK_SIZE) return VMError.StackOverflow;
                    self.call_stack[self.call_sp] = CallFrame{
                        .return_addr = self.ip + 1,
                        .base_ptr = self.bp,
                        .arg_count = arg_count,
                    };
                    self.call_sp += 1;
                    self.bp = self.sp - arg_count;
                    self.ip = func_addr;
                    continue;
                },
                .RETURN => {
                    if (self.call_sp == 0) return;
                    const frame = self.call_stack[self.call_sp - 1];
                    self.call_sp -= 1;
                    self.sp = self.bp;
                    self.bp = frame.base_ptr;
                    self.ip = frame.return_addr;
                    continue;
                },
                .LOAD_ARG => {
                    const index = self.bp + @as(usize, @intCast(instruction.operand));
                    if (index >= self.sp) return VMError.UndefinedVariable;
                    try self.push(self.stack[index]);
                },
                .STORE_ARG => {
                    const value = try self.pop();
                    const index = self.bp + @as(usize, @intCast(instruction.operand));
                    if (index >= STACK_SIZE) return VMError.StackOverflow;
                    self.stack[index] = value;
                },

                .FOR_INIT => {
                    const condition_addr = @as(usize, @intCast(instruction.operand));
                    const end_addr = @as(usize, @intCast(instruction.operand2));
                    try self.pushLoopFrame(condition_addr, end_addr, .for_loop);
                },
                .FOR_CONDITION => {
                    const condition = try self.pop();
                    if (!condition.isTruthy()) {
                        if (self.loop_sp > 0) {
                            const loop_frame = self.loop_stack[self.loop_sp - 1];
                            self.ip = loop_frame.end_addr;
                            self.popLoopFrame();
                            continue;
                        }
                    }
                },
                .FOR_INCREMENT => {
                    if (self.loop_sp > 0) {
                        const loop_frame = self.loop_stack[self.loop_sp - 1];
                        self.ip = loop_frame.start_addr;
                        continue;
                    }
                },
                .FOR_END => {
                    self.popLoopFrame();
                },

                .WHILE_START => {
                    const end_addr = @as(usize, @intCast(instruction.operand));
                    try self.pushLoopFrame(self.ip, end_addr, .while_loop);
                },
                .WHILE_CONDITION => {
                    const condition = try self.pop();
                    if (!condition.isTruthy()) {
                        if (self.loop_sp > 0) {
                            const loop_frame = self.loop_stack[self.loop_sp - 1];
                            self.ip = loop_frame.end_addr;
                            self.popLoopFrame();
                            continue;
                        }
                    }
                },
                .WHILE_END => {
                    if (self.loop_sp > 0) {
                        const loop_frame = self.loop_stack[self.loop_sp - 1];
                        self.ip = loop_frame.start_addr;
                        continue;
                    }
                },

                .BREAK => try self.breakLoop(),
                .CONTINUE => try self.continueLoop(),

                .SWITCH_START => {
                    if (self.switch_sp >= SWITCH_STACK_SIZE) return VMError.StackOverflow;
                    const end_addr = @as(usize, @intCast(instruction.operand));
                    self.switch_stack[self.switch_sp] = SwitchFrame.init(self.allocator, end_addr);
                    self.switch_sp += 1;
                },
                .CASE => {
                    const case_value = try self.pop();
                    const switch_value = try self.peek(0);
                    if (std.meta.eql(case_value, switch_value)) {
                        const case_addr = @as(usize, @intCast(instruction.operand));
                        self.ip = case_addr;
                        continue;
                    }
                },
                .DEFAULT_CASE => {
                    if (self.switch_sp > 0) {
                        self.switch_stack[self.switch_sp - 1].default_addr = @as(usize, @intCast(instruction.operand));
                    }
                },
                .SWITCH_END => {
                    _ = try self.pop();
                    if (self.switch_sp > 0) {
                        self.switch_stack[self.switch_sp - 1].deinit();
                        self.switch_sp -= 1;
                    }
                },

                .TRY_START => {
                    const catch_addr = @as(usize, @intCast(instruction.operand));
                    if (self.call_sp >= CALL_STACK_SIZE) return VMError.StackOverflow;
                    self.call_stack[self.call_sp] = CallFrame{
                        .return_addr = self.ip + 1,
                        .base_ptr = self.bp,
                        .arg_count = 0,
                        .is_exception_handler = true,
                        .catch_addr = catch_addr,
                    };
                    self.call_sp += 1;
                },
                .CATCH => {
                    if (self.current_exception) |ex| {
                        try self.push(Value{ .string = ex.message });
                        self.current_exception = null;
                    } else {
                        try self.push(Value.nil);
                    }
                },
                .THROW => {
                    const message_val = try self.pop();
                    if (message_val != .string) return VMError.TypeError;
                    try self.throwException(message_val.string);
                },
                .TRY_END => {
                    if (self.call_sp > 0 and self.call_stack[self.call_sp - 1].is_exception_handler) {
                        self.call_sp -= 1;
                    }
                },

                .ARRAY_NEW => {
                    const arr = try self.createArray();
                    try self.push(arr);
                },
                .ARRAY_GET => {
                    const index = try self.pop();
                    const arr_val = try self.pop();
                    if (arr_val != .array or index != .int) return VMError.TypeError;
                    const result = try self.arrayGet(arr_val.array, index.int);
                    try self.push(result);
                },
                .ARRAY_SET => {
                    const value = try self.pop();
                    const index = try self.pop();
                    const arr_val = try self.peek(0);
                    if (arr_val != .array or index != .int) return VMError.TypeError;
                    try self.arraySet(arr_val.array, index.int, value);
                },
                .ARRAY_LEN => {
                    const arr_val = try self.pop();
                    if (arr_val != .array) return VMError.TypeError;
                    try self.push(Value{ .int = @intCast(arr_val.array.items.items.len) });
                },
                .ARRAY_PUSH => {
                    const value = try self.pop();
                    const arr_val = try self.peek(0);
                    if (arr_val != .array) return VMError.TypeError;
                    try arr_val.array.items.append(value);
                },
                .ARRAY_POP => {
                    const arr_val = try self.peek(0);
                    if (arr_val != .array) return VMError.TypeError;
                    if (arr_val.array.items.items.len == 0) return VMError.IndexOutOfBounds;
                    const last_index = arr_val.array.items.items.len - 1;
                    const popped = arr_val.array.items.items[last_index];
                    _ = arr_val.array.items.orderedRemove(last_index);
                    try self.push(popped);
                },

                .HASHMAP_NEW => {
                    const hm = try self.createHashMap();
                    try self.push(hm);
                },
                .HASHMAP_GET => {
                    const key = try self.pop();
                    const hm_val = try self.pop();
                    if (hm_val != .hashmap or key != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(key.string);
                    const result = hm_val.hashmap.map.get(hash) orelse Value.nil;
                    try self.push(result);
                },
                .HASHMAP_SET => {
                    const value = try self.pop();
                    const key = try self.pop();
                    const hm_val = try self.peek(0);
                    if (hm_val != .hashmap or key != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(key.string);
                    try hm_val.hashmap.map.put(hash, value);
                },
                .HASHMAP_HAS => {
                    const key = try self.pop();
                    const hm_val = try self.pop();
                    if (hm_val != .hashmap or key != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(key.string);
                    const has_key = hm_val.hashmap.map.contains(hash);
                    try self.push(Value{ .bool = has_key });
                },
                .HASHMAP_DELETE => {
                    const key = try self.pop();
                    const hm_val = try self.peek(0);
                    if (hm_val != .hashmap or key != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(key.string);
                    const removed = hm_val.hashmap.map.remove(hash);
                    try self.push(Value{ .bool = removed });
                },

                .STRUCT_NEW => {
                    const s = try self.createStruct();
                    try self.push(s);
                },
                .STRUCT_GET => {
                    const field = try self.pop();
                    const struct_val = try self.pop();
                    if (struct_val != .struct_val or field != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(field.string);
                    const result = struct_val.struct_val.fields.get(hash) orelse Value.nil;
                    try self.push(result);
                },
                .STRUCT_SET => {
                    const value = try self.pop();
                    const field = try self.pop();
                    const struct_val = try self.peek(0);
                    if (struct_val != .struct_val or field != .string) return VMError.TypeError;
                    const hash = HashMap.hashString(field.string);
                    try struct_val.struct_val.fields.put(hash, value);
                },

                .FUNCTION_DEF => {
                    const arity = @as(usize, @intCast(instruction.operand));
                    const addr = @as(usize, @intCast(instruction.operand2));
                    const is_varargs = instruction.operand3 != 0;
                    const func = try self.allocator.create(Function);
                    func.* = Function{
                        .address = addr,
                        .arity = arity,
                        .name = "",
                        .is_varargs = is_varargs,
                        .local_count = 0,
                    };
                    const gc_obj = try self.gc.allocate(Value{ .function = func });
                    try self.push(gc_obj.value);
                },
                .CLOSURE_NEW => {
                    const func_val = try self.pop();
                    if (func_val != .function) return VMError.TypeError;
                    const closure = try self.allocator.create(Closure);
                    closure.* = Closure.init(self.allocator, func_val.function);
                    const gc_obj = try self.gc.allocate(Value{ .closure = closure });
                    try self.push(gc_obj.value);
                },
                .CLOSURE_CAPTURE => {
                    const capture_val = try self.pop();
                    const closure_val = try self.peek(0);
                    if (closure_val != .closure) return VMError.TypeError;
                    try closure_val.closure.captures.append(capture_val);
                },

                .STRING_CONCAT => {
                    const b = try self.pop();
                    const a = try self.pop();
                    if (a != .string or b != .string) return VMError.TypeError;
                    const result = try self.stringConcat(a.string, b.string);
                    try self.push(Value{ .string = result });
                },
                .STRING_SUBSTR => {
                    const length = try self.pop();
                    const start = try self.pop();
                    const str = try self.pop();
                    if (str != .string or start != .int or length != .int) return VMError.TypeError;
                    const result = try self.stringSubstr(str.string, start.int, length.int);
                    try self.push(Value{ .string = result });
                },
                .STRING_LEN => {
                    const str = try self.pop();
                    if (str != .string) return VMError.TypeError;
                    try self.push(Value{ .int = @intCast(str.string.len) });
                },
                .STRING_COMPARE => {
                    const b = try self.pop();
                    const a = try self.pop();
                    if (a != .string or b != .string) return VMError.TypeError;
                    const cmp = std.mem.order(u8, a.string, b.string);
                    var result: i64 = undefined;
                    if (cmp == .lt) {
                        result = -1;
                    } else if (cmp == .eq) {
                        result = 0;
                    } else {
                        result = 1;
                    }
                    try self.push(Value{ .int = result });
                },
                .GC_COLLECT => {
                    try self.gc.fullCollect(self);
                },
                .WEAK_REF_NEW => {
                    const target = try self.pop();
                    const weak_ref = try self.createWeakRef(target);
                    try self.push(weak_ref);
                },
                .WEAK_REF_GET => {
                    const weak_ref_val = try self.pop();
                    if (weak_ref_val != .int) return VMError.TypeError;
                    const weak_ref = @as(*WeakRef, @ptrFromInt(@as(usize, @bitCast(@as(isize, weak_ref_val.int)))));
                    const result = weak_ref.get() orelse Value.nil;
                    try self.push(result);
                },

                .PRINT => {
                    const value = try self.pop();
                    const str = try value.toString(self.allocator);
                    defer if (value != .string) self.allocator.free(str);
                    print("{s}\n", .{str});
                },
                .INPUT => {
                    const stdin = std.io.getStdIn().reader();
                    const input = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 1024);
                    defer self.allocator.free(input);
                    const str = try self.allocator.dupe(u8, input);
                    try self.push(Value{ .string = str });
                },

                .HALT => return,
                .NOP => {},
            }
            self.ip += 1;
        }
    }

    pub fn printStack(self: *VM) void {
        print("Stack (SP={}): [", .{self.sp});
        for (0..self.sp) |i| {
            if (i > 0) print(", ", .{});
            const str = self.stack[i].toString(self.allocator) catch "?";
            defer if (self.stack[i] != .string) self.allocator.free(str);
            print("{s}", .{str});
        }
        print("]\n", .{});
    }

    pub fn printGlobals(self: *VM) void {
        print("Globals: [");
        var first = true;
        for (self.globals, 0..) |global, i| {
            if (global != .nil) {
                if (!first) print(", ", .{});
                first = false;
                const str = global.toString(self.allocator) catch "?";
                defer if (global != .string) self.allocator.free(str);
                print("{}:{s}", .{ i, str });
            }
        }
        print("]\n", .{});
    }

    pub fn printMemoryStats(self: *VM) void {
        print("Memory: Young={}, Old={}, Collections={}\n", .{ self.gc.young_gen.items.len, self.gc.old_gen.items.len, self.gc.collection_count });
    }
};

pub fn makeInst(opcode: OpCode) Instruction {
    return .{ .opcode = opcode };
}
pub fn makeInst1(opcode: OpCode, op1: i32) Instruction {
    return .{ .opcode = opcode, .operand = op1 };
}
pub fn makeInst2(opcode: OpCode, op1: i32, op2: i32) Instruction {
    return .{ .opcode = opcode, .operand = op1, .operand2 = op2 };
}
pub fn makeInst3(opcode: OpCode, op1: i32, op2: i32, op3: i32) Instruction {
    return .{ .opcode = opcode, .operand = op1, .operand2 = op2, .operand3 = op3 };
}
