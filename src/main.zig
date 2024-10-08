const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
});

const rGenerator = std.rand.DefaultPrng;
var rnd = rGenerator.init(0);
const rand = rnd.random();

const WINDOW_W = 1900;
const WINDOW_H = 1080;

const PARTICLE_COUNT = 1000;

const POINTS_PER_QUAD = 1;
const particleRadius = 10;

const VISUALISE_TREE = false;

var pa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const arena = pa.allocator();

// global state of the app
var STATE: AppState = undefined;

// handle for point
// DOD principle
const pointHandle = struct {
    pointer: u16,
};

//
const Point = @Vector(2, i32);

// get magnitude of a vector
fn getDistance(a: Point) u32 {
    return std.math.sqrt((@as(u32, @intCast(std.math.pow(i32, a[0], 2))) + @as(u32, @intCast(std.math.pow(i32, a[1], 2)))));
}

const Particle = struct {
    position: Point,
    velocity: @Vector(2, i32),

    fn initRandom() Particle {
        return .{
            .position = Point{
                rand.intRangeAtMost(i32, 0, WINDOW_W),
                rand.intRangeAtMost(i32, 0, WINDOW_H),
            },
            .velocity = .{
                rand.intRangeAtMost(i8, -20, 20),
                rand.intRangeAtMost(i8, -20, 20),
            },
        };
    }

    fn collides(self: Particle, other: Particle) bool {
        return getDistance(self.position - other.position) <= particleRadius * 2;
    }

    fn eql(self: Particle, other: Particle) bool {
        const tst = self.position == other.position;
        return tst[0] and tst[1];
    }

    fn applyMovement(self: *Particle, allocator: std.mem.Allocator) void {
        const particlesL = STATE.quadTree.queryRange(Rectangle{
            .x = @as(u16, @intCast(std.math.clamp(self.position[0] - particleRadius, 0, WINDOW_W * 2))),
            .y = @as(u16, @intCast(std.math.clamp(self.position[1] - particleRadius, 0, WINDOW_H * 2))),
            .w = particleRadius * 2,
            .h = particleRadius * 2,
        }, allocator);

        if (particlesL) |particles| {
            for (particles.items) |particle| {
                // if is the same particle
                if (STATE.getParticle(particle).eql(self.*)) {
                    continue;
                }

                // if particle collision
                if (STATE.getParticle(particle).collides(self.*)) {
                    var part = STATE.getParticleRef(particle);
                    const bounce = (self.position - part.position);
                    self.velocity = bounce;
                    part.velocity = -bounce;
                }
            }
        }

        if (self.position[0] >= WINDOW_W or self.position[0] <= 0) {
            self.velocity[0] = -self.velocity[0];
        }
        self.position[0] += self.velocity[0];

        if (self.position[1] >= WINDOW_W or self.position[1] <= 0) {
            self.velocity[1] = -self.velocity[1];
        }
        self.position[1] += self.velocity[1];

        // see if collision
    }
};

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
    // points in this tree
    points: [POINTS_PER_QUAD]pointHandle,
    pointsInArray: u8,

    isDivided: bool,

    fn draw(self: Self, c: raylib.Color) void {
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

        for (0..self.pointsInArray) |val| {
            if (rect.isInside(STATE.getPoint(self.points[val]))) {
                list.append(self.points[val]) catch unreachable;
            }
        }
        if (!self.isDivided) {
            return list;
        }

        self.tl.addQueryToList(rect, &list, allocator);
        self.tr.addQueryToList(rect, &list, allocator);
        self.bl.addQueryToList(rect, &list, allocator);
        self.br.addQueryToList(rect, &list, allocator);
        return list;
    }

    // just a fn that adds the items into an arraylist
    fn addQueryToList(t: Tree, rect: Rectangle, list: *std.ArrayList(pointHandle), allocator: std.mem.Allocator) void {
        const t_items = t.queryRange(rect, allocator);
        if (t_items) |items| {
            for (items.items) |item| {
                list.append(item) catch unreachable;
            }
        }
    }
};

const AppState = struct {
    particleList: std.ArrayList(Particle),
    quadTree: Tree,

    fn init(allocator: std.mem.Allocator) !AppState {
        var app: AppState = undefined;
        app.particleList = std.ArrayList(Particle).init(allocator);
        app.quadTree = Tree.init(Rectangle{ .x = 0, .y = 0, .w = WINDOW_W, .h = WINDOW_H });
        return app;
    }

    fn getPoint(self: AppState, point: pointHandle) Point {
        return self.particleList.items[point.pointer].position;
    }

    fn getParticle(self: AppState, point: pointHandle) Particle {
        return self.particleList.items[point.pointer];
    }

    fn getParticleRef(self: *AppState, point: pointHandle) *Particle {
        return &self.particleList.items[point.pointer];
    }
};

pub fn main() !void {
    STATE = try AppState.init(arena);

    //raylib init
    raylib.InitWindow(WINDOW_W, WINDOW_H, "win");
    defer raylib.CloseWindow();

    var insertpool = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const insertArena = insertpool.allocator();

    var collisionPool = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const collisionArena = collisionPool.allocator();

    // add particles
    for (0..PARTICLE_COUNT) |i| {
        try STATE.particleList.append(Particle.initRandom());
        try STATE.quadTree.insert(pointHandle{ .pointer = @intCast(i) }, insertArena);
    }

    //STATE.quadTree.prettyPrint(1);
    raylib.SetTargetFPS(60);

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.WHITE);

        // draw quadttee
        if (VISUALISE_TREE) {
            STATE.quadTree.draw(raylib.BLACK);
        }

        // draw points
        for (STATE.particleList.items) |point| {
            raylib.DrawCircle(@intCast(point.position[0]), @intCast(point.position[1]), particleRadius, raylib.PURPLE);
        }

        // move particles
        for (0..PARTICLE_COUNT) |i| {
            STATE.particleList.items[i].applyMovement(collisionArena);
            _ = collisionPool.reset(.retain_capacity);
        }

        _ = insertpool.reset(.retain_capacity);
        STATE.quadTree.isDivided = false;
        // reconstruct quad tree from zero
        for (0..PARTICLE_COUNT) |i| {
            try STATE.quadTree.insert(pointHandle{ .pointer = @intCast(i) }, insertArena);
        }
    }
}
