const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
});

const rGenerator = std.rand.DefaultPrng;
var rnd = rGenerator.init(0);
const rand = rnd.random();

const WINDOW_W = 800;
const WINDOW_H = 800;

const POINTS_PER_QUAD = 1;

var pa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const arena = pa.allocator();

// global state of the app
var STATE: AppState = undefined;

//
const pointHandle = struct {
    pointer: u8,
};

const Point = @Vector(2, u16);

var RectDebugList: std.ArrayList(Rectangle) = undefined;

const Rectangle = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    fn isInside(self: Rectangle, point: Point) bool {
        if (point[0] < self.x + self.w and point[0] > self.x) {
            if (point[1] < self.y + self.h and point[1] > self.y) {
                return true;
            }
        }
        return false;
    }
    fn isOverlapping(self: Rectangle, rect: Rectangle) bool {
        if (rect.x < self.x + self.w and rect.x + rect.w > self.x) {
            if (rect.y < self.y + self.h and rect.y + rect.h > self.y) {
                return true;
            }
        }
        return false;
    }
    fn draw(self: Rectangle, c: raylib.Color) void {
        raylib.DrawRectangle(self.x, self.y, self.w, self.h, c);
        raylib.DrawRectangleLines(self.x, self.y, self.w, self.h, raylib.BLACK);
    }
};

// quad tree stuct
// tree strucdt does not own points it has point handles witch are indexes to a list of points in appstate
const Tree = struct {
    const Self = @This();

    // top botton left right subtrees
    tl: *Tree,
    tr: *Tree,
    bl: *Tree,
    br: *Tree,

    boundry: Rectangle,
    // points in this thing
    points: [POINTS_PER_QUAD]pointHandle,
    pointsInArray: u8,

    isDivided: bool,

    fn addlist(self: Self) void {
        RectDebugList.append(self.boundry) catch unreachable;

        if (self.isDivided) {
            self.tl.addlist();
            self.tr.addlist();
            self.bl.addlist();
            self.br.addlist();
        }
    }

    fn draw(self: Self, c: raylib.Color) void {
        //raylib.DrawRectangleLines(self.boundry.x, self.boundry.y, self.boundry.w, self.boundry.h, c);

        self.boundry.draw(c);

        if (self.isDivided) {
            self.tl.draw(raylib.RED);
            self.tr.draw(raylib.GREEN);
            self.bl.draw(raylib.BLUE);
            self.br.draw(raylib.YELLOW);
        }
    }
    fn prettyPrint(self: Self, depth: u16) void {
        std.debug.print(
            "boundry x:{d} y:{d} w:{d} h:{d}\n",
            .{ self.boundry.x, self.boundry.y, self.boundry.w, self.boundry.h },
        );
        if (!self.isDivided) {
            return;
        }

        for (0..depth) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("top left(red): ", .{});
        self.tl.prettyPrint(depth + 1);

        for (0..depth) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("top right(green): ", .{});
        self.tr.prettyPrint(depth + 1);

        for (0..depth) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("bottom left(blue): ", .{});
        self.bl.prettyPrint(depth + 1);

        for (0..depth) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("bottom right(yeallow): ", .{});
        self.br.prettyPrint(depth + 1);
    }

    fn init(boundry: Rectangle) Self {
        return .{
            .tl = undefined,
            .tr = undefined,
            .bl = undefined,
            .br = undefined,
            .isDivided = false,
            .boundry = boundry,
            .points = undefined,
            .pointsInArray = 0,
        };
    }

    fn subDivide(self: *Self, allocator: std.mem.Allocator) !void {
        self.tl = try allocator.create(Tree);
        self.tr = try allocator.create(Tree);
        self.bl = try allocator.create(Tree);
        self.br = try allocator.create(Tree);

        self.tl.* = Tree.init(Rectangle{
            .x = self.boundry.x,
            .y = self.boundry.y,
            .w = self.boundry.w / 2,
            .h = self.boundry.h / 2,
        });

        self.tr.* = Tree.init(Rectangle{
            .x = self.boundry.x + self.boundry.w / 2,
            .y = self.boundry.y,
            .w = self.boundry.w / 2,
            .h = self.boundry.h / 2,
        });

        self.bl.* = Tree.init(Rectangle{
            .x = self.boundry.x,
            .y = self.boundry.y + self.boundry.h / 2,
            .w = self.boundry.w / 2,
            .h = self.boundry.h / 2,
        });

        self.br.* = Tree.init(Rectangle{
            .x = self.boundry.x + self.boundry.w / 2,
            .y = self.boundry.y + self.boundry.h / 2,
            .w = self.boundry.w / 2,
            .h = self.boundry.h / 2,
        });

        self.isDivided = true;
    }

    fn insert(self: *Self, point: pointHandle, allocator: std.mem.Allocator) !void {
        // if the point is not inside this tree just exit
        if (!self.boundry.isInside(STATE.getPoint(point))) {
            return;
        }

        if (self.pointsInArray < self.points.len) {
            self.points[self.pointsInArray] = point;
            self.pointsInArray += 1;
            return;
        }
        // else subdivide
        if (!self.isDivided) {
            try self.subDivide(allocator);
        }
        //and add point to the other trees
        try self.tl.insert(point, allocator);
        try self.tr.insert(point, allocator);
        try self.bl.insert(point, allocator);
        try self.br.insert(point, allocator);
    }

    // find points in range
    // ALLOCATOR NEEDS TO BE ARENA
    fn queryRange(self: Self, rect: Rectangle, allocator: std.mem.Allocator) ?std.ArrayList(pointHandle) {
        if (!self.boundry.isOverlapping(rect)) {
            return null;
        }
        // i dont really like creating the array here
        var list = std.ArrayList(pointHandle).init(allocator);

        for (0..self.points.len) |val| {
            if (rect.isInside(STATE.getPoint(self.points[val]))) {
                list.append(self.points[val]);
            }
        }
        if (!self.isDivided) {
            return list;
        }

        self.tl.addQueryToList(rect, list, allocator);
        self.tr.addQueryToList(rect, list, allocator);
        self.bl.addQueryToList(rect, list, allocator);
        self.br.addQueryToList(rect, list, allocator);
    }

    // just a fn that adds the items into an arraylist
    fn addQueryToList(t: Tree, rect: Rectangle, list: *std.ArrayList(pointHandle), allocator: std.heap.ArenaAllocator) void {
        const t_items = t.queryRange(rect, allocator);
        if (t_items) |items| {
            for (items.items) |item| {
                list.append(item);
            }
        }
    }
};

const AppState = struct {
    pointList: std.ArrayList(Point),
    quadTree: Tree,

    fn init(allocator: std.mem.Allocator) !AppState {
        var app: AppState = undefined;
        const pointList = std.ArrayList(Point).init(allocator);
        app.pointList = pointList;
        app.quadTree = Tree.init(Rectangle{ .x = 0, .y = 0, .w = WINDOW_W, .h = WINDOW_H });
        return app;
    }

    fn getPoint(self: AppState, point: pointHandle) Point {
        return self.pointList.items[point.pointer]; // or somthing like thai
    }
};

pub fn main() !void {
    STATE = try AppState.init(arena);
    RectDebugList = std.ArrayList(Rectangle).init(arena);

    //
    raylib.InitWindow(WINDOW_W, WINDOW_H, "win");
    defer raylib.CloseWindow();

    const pointcount = 100;

    var insertpool = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const insertArena = insertpool.allocator();

    for (0..pointcount) |i| {
        try STATE.pointList.append(Point{ rand.intRangeAtMost(u16, 0, WINDOW_W), rand.intRangeAtMost(u16, 0, WINDOW_H) });
        try STATE.quadTree.insert(pointHandle{ .pointer = @intCast(i) }, insertArena);
    }
    //STATE.quadTree.prettyPrint(1);

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.WHITE);
        STATE.quadTree.draw(raylib.BLACK);
        for (STATE.pointList.items) |point| {
            raylib.DrawCircle(@intCast(point[0]), @intCast(point[1]), 5, raylib.PURPLE);
        }
    }
}
