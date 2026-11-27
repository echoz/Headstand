// Pocket stand for two classic Oral-B heads. Dimensions in millimetres.
// Base and lid use local shell coordinates. Open shows the working counter pose.
part = "open"; // [open, closed, base, lid]

/* [Brush fit] */
// Diameter inside the head at the plane supporting the heel.
peg_diameter = 5.6; // [4:0.2:7]
// Distance from the supported heel to the end of the nose.
peg_insertion = 7; // [4:0.2:8.6]

/* [Hidden] */
$fn = 80;
eps = 0.025;
span = 33;
front = 25;
back = 2.7;
corner = 4.8;
wall = 1.6;
deck = 2;
pad_lift = 1.55;
leaf_angle = 6;
axis_z = 7.2;
pin_bore = 2.25;
barrel_r = 2.35;
hinge_span = 27;
knuckle_gap = 0.45;
station = [-4.2, -14];
counter_lift = front*sin(leaf_angle) - axis_z*(1-cos(leaf_angle));

assert(peg_diameter >= 4 && peg_diameter <= 7);
assert(peg_insertion >= 4 && peg_insertion <= 8.6);

module shell_form(levels) {
    // Each corner keeps its centre through the bevels so every side face is planar.
    centers = [[span/2-corner, -front+corner], [span/2-corner, -back-corner],
               [corner-span/2, -back-corner], [corner-span/2, -front+corner]];
    arc_steps = 20;
    ring = 4*(arc_steps + 1);
    points = [for (level = levels, q = [0:3], step = [0:arc_steps])
        let (angle = 90*(q-1) + step*90/arc_steps, r = corner - level.y)
        [centers[q].x + r*cos(angle), centers[q].y + r*sin(angle), level.x]];
    faces = concat([[for (i = [0:ring-1]) i]],
        [for (j = [0:len(levels)-2], i = [0:ring-1])
            let (next = (i+1)%ring)
            [j*ring+i, (j+1)*ring+i, (j+1)*ring+next, j*ring+next]],
        [[for (i = [ring-1:-1:0]) (len(levels)-1)*ring+i]]);
    polyhedron(points, faces, convexity = 4);
}

// A shallow gutter descends from the centre and both corners to the low-edge ports.
module drain_ports() {
    for (side = [-1, 1]) {
        port_x = side * 7.5;
        for (end_x = [0, side*12.5])
            hull() for (x = [end_x, port_x]) {
                depth = x == port_x ? 0.40 : 0.10;
                translate([x-0.1, -front+wall-0.28, deck-depth])
                    cube([0.2, 1.65, depth+0.52]);
            }
        translate([port_x, -front+wall+1.5, deck-0.40])
            rotate([90, 0, 0]) linear_extrude(height = wall+2)
                polygon([[-2.6, 0], [2.6, 0], [2.6, 1.6],
                         [0.65, 3.55], [-0.65, 3.55], [-2.6, 1.6]]);
    }
}

function landing_z(y) = -(y+front)*tan(leaf_angle);

module landing() {
    // The inward end blends back into the exterior over a short ramp.
    intersection() {
        translate([0, -21.65, -1])
            linear_extrude(height = 1.5) offset(r = 1.3)
                square([24.4, 3.0], center = true);
        yz_prism(-14, 28)
            polygon([[-25, landing_z(-25)], [-19.7, landing_z(-19.7)],
                     [-18.7, 0.2], [-18.7, 0.45], [-25, 0.45]]);
    }
}

module shell() {
    difference() {
        shell_form([[0, 0.7], [0.7, 0], [axis_z-0.4, 0], [axis_z, 0.35]]);
        shell_form([[deck, wall+0.4], [deck+0.4, wall],
                    [axis_z-0.42, wall], [axis_z+eps, wall-0.30]]);
        drain_ports();
    }
}

module peg() {
    heel_r = peg_diameter/2;
    shoulder_r = heel_r - 0.8;
    round_r = min(1.2, shoulder_r - 0.45);
    tip = pad_lift + peg_insertion;
    shoulder_z = tip - round_r;
    root_r = heel_r + 0.8 * pad_lift / (peg_insertion - round_r);
    rotate_extrude()
        polygon(concat([[0, -0.65], [root_r + 0.45, -0.65], [root_r + 0.45, 0],
                        [root_r + 0.12, 0.12], [heel_r, pad_lift]],
            [for (a = [0:10:90])
                [shoulder_r - round_r + round_r*cos(a), shoulder_z + round_r*sin(a)]],
            [[0, tip]]));
}

module brush_station() {
    // Extend each root through the sloping deck. The tops share the level heel plane.
    translate([station.x, station.y, deck]) rotate([-leaf_angle, 0, 0]) {
        peg();
        for (a = [90, 210, 330])
            rotate([0, 0, a]) hull()
                for (r = [5.8, 6.6])
                    translate([r, 0, -1])
                        cylinder(h = pad_lift + 1, r1 = 1.25, r2 = 1, $fn = 32);
    }
}

// Extrude a Y,Z section in the +X direction.
module yz_prism(x, length) {
    translate([x, 0, 0])
        multmatrix([[0,0,1,0], [1,0,0,0], [0,1,0,0], [0,0,0,1]])
            linear_extrude(height = length) children();
}

module knuckle(index) {
    length = (hinge_span - 2*knuckle_gap)/3;
    start = -hinge_span/2 + index*(length + knuckle_gap);
    bore_r = pin_bore/2;
    yz_prism(start, length)
        difference() {
            hull() {
                translate([0, axis_z]) circle(r = barrel_r);
                // Bottom of the web grows out from the rim at about 45 degrees.
                translate([-back - 0.7, 1.2]) square([0.55, axis_z - 3.05]);
            }
            translate([0, axis_z]) hull() {
                circle(r = bore_r);
                polygon([[-bore_r/sqrt(2), bore_r/sqrt(2)],
                         [0, bore_r*sqrt(2)], [bore_r/sqrt(2), bore_r/sqrt(2)]]);
            }
        }
}

module opening_stops() {
    // Both faces rotate onto the vertical hinge midplane at full opening.
    function stop_y(z) = (z-axis_z)*tan(leaf_angle);
    for (x = [-8.8, 8.8])
        yz_prism(x - 1.7, 3.4)
            polygon([[-back - 1, 0], [stop_y(0)-0.35, 0], [stop_y(0.4), 0.4],
                     [stop_y(2.15), 2.15], [-back, 2.85], [-back - 1, 2.85]]);
}

// These profiles use the working pose before its final lift onto the counter.
// The spring runs along X underneath the barrel, clear of the pin. Its tooth
// points down so the user can lift the empty stand and press the tab from below.
module open_spring() {
    yz_prism(-6.45, 1.55)
        polygon([[-3.6, 1.25], [-1.3, 2.03], [0.42, 2.03],
                 [0.42, 3.1], [-3.6, 3.1]]);
    yz_prism(-5.2, 9.35)
        polygon([[-1.65, 2.03], [0.42, 2.03], [0.42, 3.1], [-1.65, 3.1]]);
    yz_prism(1.65, 2.5)
        polygon([[-1.65, 2.03], [0.60, 2.03], [0.78, 1.38],
                 [0.96, 1.38], [1.80, 2.19], [1.80, 3.1], [-1.65, 3.1]]);
    // A low finger pad straddles the gap; its narrow end clears the keeper.
    yz_prism(2.70, 1.45)
        polygon([[-1.42, 0.22], [-0.38, 0.22], [-0.38, 2.22], [-1.42, 2.22]]);
    translate([0, 0, -0.30]) linear_extrude(height = 0.68)
        offset(r = 0.32) offset(delta = -0.32) polygon([
            [-1.95, -1.54], [4.18, -1.54], [4.18, -0.16],
            [0.60, -0.16], [0.60, 1.38], [-1.95, 1.38]
        ]);
}

module open_keeper() {
    // The far face of the tooth engages the spring after it rides over the ramp.
    yz_prism(1.4, 3.0)
        polygon([[0.02, 0.68], [3.8, 0.68], [3.8, 1.65], [1.95, 1.65],
                 [1.55, 1.10], [0.69, 1.10], [0.54, 1.95],
                 [0.30, 1.95], [0.02, 1.70]]);
}

module front_latch_section(width, points) {
    yz_prism(-width/2, width)
        offset(r = 0.10, $fn = 16) offset(delta = -0.10)
            polygon([for (p = points) [-front - p.x, p.y]]);
}

module spring_clip() {
    // One free wall with a thumb lip. Pull outward to free the lid's ridge.
    front_latch_section(7, [
        [-0.95, 0.42], [1.55, 0.42], [2, 0.87], [2, 9.75],
        [2.30, 10.05], [2.30, 10.6], [1.14, 10.8], [0.34, 9.9],
        [1.0, 9.45], [1.0, 2.1], [-0.35, 1.15], [-0.95, 1.15]
    ]);
}

module catch_ridge() {
    front_latch_section(7.8, [
        [-0.35, 4.65], [0, 4.65], [0.78, 5.0], [0.78, 5.28],
        [0, 6.10], [-0.35, 6.10]
    ]);
}

module leaf(is_base) {
    union() {
        shell();
        landing();
        opening_stops();
        for (i = is_base ? [0, 2] : [1]) knuckle(i);
        brush_station();
        if (is_base) spring_clip();
        else catch_ridge();
    }
}

module swing(angle) {
    translate([0, 0, axis_z]) rotate([angle, 0, 0])
        translate([0, 0, -axis_z]) children();
}

module base() {
    leaf(true);
    swing(-leaf_angle) open_spring();
}

module lid() {
    difference() {
        rotate([0, 0, 180]) leaf(false);
        // Clear the spring's upward stroke below the central bearing web.
        swing(leaf_angle) translate([-4.5, -2.2, 1.12]) cube([9, 4.24, 3.50]);
    }
    swing(leaf_angle) open_keeper();
}

if (part == "base") base();
else if (part == "lid") lid();
else if (part == "open") {
    translate([0, 0, counter_lift]) {
        color("#54807c") swing(leaf_angle) base();
        color("#9dbbb2") swing(-leaf_angle) lid();
    }
} else if (part == "closed") {
    color("#54807c") base();
    color("#9dbbb2") swing(180) lid();
} else assert(false, str("Unknown part: ", part));
