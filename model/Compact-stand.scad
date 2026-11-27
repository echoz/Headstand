// Compact travel stand for two classic round brush heads. Dimensions in mm.
// The heel rests on three pads. Size the locating pegs to the free space
// inside your heads, including clearance below the internal drive parts.

/* [Unmeasured peg fit — tune after a trial print] */
// Diameter at the plane where the brush heel rests.
peg_diameter = 5.6; // [4:0.2:7]
// Distance from the heel plane to the top of the rounded nose.
peg_insertion = 7; // [4:0.2:10]

/* [Hidden] */
$fn = 96;
base_length = 50;
base_width = 32;
base_height = 4.4;
corner_radius = 10;
station_pitch = 24;
pad_height = 0.8;
seat_z = base_height + pad_height;
overlap = 0.04;

module base() {
    lower_bevel = 0.8;
    upper_round = 1.6;
    // Quarter-round at the deck and a 45 degree bevel from the flat sole.
    corner_profile = concat(
        [[0, 0], [corner_radius - lower_bevel, 0], [corner_radius, lower_bevel]],
        [for (a = [0:10:90]) [
            corner_radius - upper_round + upper_round * cos(a),
            base_height - upper_round + upper_round * sin(a)
        ]],
        [[0, base_height]]
    );
    hull()
        for (x = [-1, 1], y = [-1, 1])
            translate([x * (base_length/2 - corner_radius), y * (base_width/2 - corner_radius), 0])
                rotate_extrude() polygon(corner_profile);
}

module locating_peg() {
    seat_radius = peg_diameter / 2;
    shoulder_radius = seat_radius - 0.8;
    nose_round = min(1.2, shoulder_radius - 0.45);
    top_z = seat_z + peg_insertion;
    shoulder_z = top_z - nose_round;
    taper = (seat_radius - shoulder_radius) / (shoulder_z - seat_z);
    deck_radius = seat_radius + taper * pad_height;
    profile = concat(
        [[0, base_height - overlap], [deck_radius + 0.45, base_height - overlap],
         [deck_radius + 0.45, base_height], [deck_radius + 0.12, base_height + 0.12],
         [seat_radius, seat_z]],
        [for (a = [0:10:90]) [
            shoulder_radius - nose_round + nose_round * cos(a),
            shoulder_z + nose_round * sin(a)
        ]],
        [[0, top_z]]
    );
    rotate_extrude() polygon(profile);
}

module heel_pad() {
    // The small flat spans the provisional heel rim and leaves an air gap
    // all the way to the deck edge between successive pads.
    hull()
        for (r = [5.8, 6.6])
            translate([r, 0, base_height - overlap])
                cylinder(h = pad_height + overlap, r1 = 1.25, r2 = 1, $fn = 36);
}

union() {
    base();
    for (x = [-station_pitch/2, station_pitch/2])
        translate([x, 0, 0]) {
            locating_peg();
            for (a = [90, 210, 330])
                rotate([0, 0, a]) heel_pad();
        }
}
