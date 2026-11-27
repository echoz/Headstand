// Pocket stand for two classic Oral-B heads. Dimensions in millimetres.
// Base and lid use their open assembly coordinates, with the runners on Z=0.
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
runner_height = 1;
pad_lift = 0.8;
axis_z = 7.2;
pin_bore = 2.25;
barrel_r = 2.35;
hinge_span = 27;
knuckle_gap = 0.45;
station = [-4.2, -14];

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

module drain_section(x, depth) {
    // Sloping sides blend into the deck. The peaked roof forms the wall port.
    yz_prism(x - eps, 2*eps)
        translate([station.y, deck])
            polygon([[-1.5, -depth], [1.5, -depth], [2.2, 0.7-depth],
                     [2.2, 1.35], [0.65, 2.9], [-0.65, 2.9], [-2.2, 1.35],
                     [-2.2, 0.7-depth]]);
}

module heel_drains() {
    // Each rill starts under the hollow heel, misses the pads and falls to daylight.
    for (side = [-1, 1]) hull() {
        drain_section(station.x + side*4.25, 0.07);
        drain_section(side*(span/2 + 0.4), 0.70);
    }
}

module runners() {
    // The flared rails shorten the bridges under the slab and leave both ends open.
    for (y = [station.y-8, station.y, station.y+8]) hull()
        for (x = [-11.5, 11.5])
            translate([x, y, -runner_height])
                cylinder(h = runner_height + eps, r1 = 1.4, r2 = 1.4 + runner_height + eps);
}

module shell() {
    difference() {
        shell_form([[0, 0.7], [0.7, 0], [axis_z-0.4, 0], [axis_z, 0.35]]);
        shell_form([[deck, wall+0.4], [deck+0.4, wall],
                    [axis_z-0.42, wall], [axis_z+eps, wall-0.30]]);
        heel_drains();
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
        polygon(concat([[0, -eps], [root_r + 0.45, -eps], [root_r + 0.45, 0],
                        [root_r + 0.12, 0.12], [heel_r, pad_lift]],
            [for (a = [0:10:90])
                [shoulder_r - round_r + round_r*cos(a), shoulder_z + round_r*sin(a)]],
            [[0, tip]]));
}

module brush_station() {
    translate([0, 0, deck]) {
        peg();
        for (a = [90, 210, 330])
            rotate([0, 0, a]) hull()
                for (r = [5.8, 6.6])
                    translate([r, 0, -eps])
                        cylinder(h = pad_lift + eps, r1 = 1.25, r2 = 1, $fn = 32);
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
    // The two pairs of faces meet at y=0 when the leaves share the counter plane.
    for (x = [-8.8, 8.8])
        yz_prism(x - 1.7, 3.4)
            polygon([[-back - 1, 0], [-0.4, 0], [0, 0.4],
                     [0, 2.15], [-back, 2.85], [-back - 1, 2.85]]);
}

module front_latch_section(width, points) {
    yz_prism(-width/2, width)
        offset(r = 0.10, $fn = 16) offset(delta = -0.10)
            polygon([for (p = points) [-front - p.x, p.y]]);
}

module spring_clip() {
    // One free wall with a thumb lip. Pull outward to free the lid's ridge.
    front_latch_section(7, [
        [-0.95, 0], [1.55, 0], [2, 0.45], [2, 9.75],
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
        runners();
        opening_stops();
        for (i = is_base ? [0, 2] : [1]) knuckle(i);
        translate(station) brush_station();
        if (is_base) spring_clip();
        else catch_ridge();
    }
}

module lid() {
    rotate([0, 0, 180]) leaf(false);
}

translate([0, 0, runner_height])
if (part == "base") leaf(true);
else if (part == "lid") lid();
else if (part == "open" || part == "closed") {
    color("#54807c") leaf(true);
    color("#9dbbb2")
        translate([0, 0, axis_z])
            rotate([part == "closed" ? 180 : 0, 0, 0])
                translate([0, 0, -axis_z]) lid();
} else assert(false, str("Unknown part: ", part));
