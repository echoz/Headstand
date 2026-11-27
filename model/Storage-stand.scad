// Level, print-in-place travel stand. All dimensions are in millimetres.
// Both heads load into the base with their bristles pointing toward the outside.
use <Folding-stand.scad>
use <Compact-stand.scad>

part = "open"; // [open, closed, base, lid]

/* [Brush fit] */
peg_diameter = 5.6; // [4:0.2:6.2]
peg_insertion = 7; // [4:0.2:7.2]

/* [Hidden] */
$fn = 64;
eps = 0.025;
axis_z = 12.8;
case_y = -24;
wall = 1.6;
floor_z = 2.4;
rail_height = 1;
shaft_z = 12.65;
lane = 7.35;
yaw = 8;
base_peg = [-13,-25.4];
lid_peg = [13,-22.6]; // in the closed XY plan
assert(peg_diameter >= 4 && peg_diameter <= 6.2);
assert(peg_insertion >= 4 && peg_insertion <= 7.2);

module outline(inset=0) {
    // The narrowed middle accommodates the clasp within the width of the crown bays.
    side = [[-42.0,21.9],[-36.7,23.65],[-20.5,23.65],[-11.5,17.8],
            [11.5,17.8],[20.5,23.65],[36.7,23.65],[42.0,21.9]];
    translate([0,case_y]) offset(delta=-inset) offset(r=2.3) offset(delta=-2.3)
        polygon(concat(side,[for(i=[len(side)-1:-1:0]) [side[i].x,-side[i].y]]));
}

module body() {
    difference() {
        linear_extrude(height=axis_z-rail_height) outline();
        translate([0,0,floor_z-rail_height]) linear_extrude(height=axis_z) outline(wall);
    }
}

module head_frame(sign) {
    translate([0,case_y-sign*lane,0]) rotate([0,0,sign==1 ? yaw : yaw+180])
        children();
}

// Recess the bristle tips on both faces. The matching exterior pads keep the
// floor thick at the recess and support the vent perimeters on the print bed.
module crown_bays(margin=0) {
    for(sign=[-1,1]) head_frame(sign)
        translate([28.5,-12]) offset(r=3+margin) square([19,12],center=true);
}

module outlet_channels(station) {
    // Each split rail supports the port rim while its centre drains to either edge.
    for(x=[station.x,-34,-26,26,34])
        translate([x,case_y,0]) hull()
            for(level=[[-eps,3.3],[rail_height,1.3]])
                translate([0,0,level.x]) linear_extrude(height=eps)
                    square([level.y,60],center=true);
}

module storage_rails(station) {
    difference() {
        intersection() {
            linear_extrude(height=rail_height+eps) outline();
            union() {
                linear_extrude(height=rail_height+eps) difference() {
                    outline();
                    outline(1.8);
                }
                linear_extrude(height=rail_height+eps) crown_bays(0.9);
                for(x=[-34,-26,-18.5,-13,-5,4,13,18.5,26,34])
                    translate([x,case_y,0]) hull()
                        for(z=[0,rail_height])
                            translate([0,0,z]) linear_extrude(height=eps)
                                square([5+2*z,52],center=true);
            }
        }
        outlet_channels(station);
    }
}

module sole_slot(x, y, length, diameter) {
    hull() for(dy=[-length/2,length/2])
        translate([x,y+dy,-eps]) cylinder(d=diameter,h=floor_z+2*eps);
}

module drains(station) {
    for(dy=[-4.45,4.45]) sole_slot(station.x,station.y+dy,0.5,1.9);
    for(sign=[-1,1], x=[26,34])
        sole_slot(sign*x,case_y-sign*15.2,6.4,2.2);
}

module storage_shell(station) {
    difference() {
        union() {
            translate([0,0,rail_height]) body();
            storage_rails(station);
        }
        drains(station);
        translate([0,0,floor_z-0.85]) linear_extrude(height=0.85+eps)
            intersection() {
                outline(wall+0.2);
                crown_bays();
            }
    }
}

module storage_station(station) {
    // Define the taper from the fixed heel plane; changing insertion preserves fit there.
    radius = peg_diameter/2;
    shoulder = radius-0.8;
    nose = min(1.2,shoulder-0.45);
    lift = 0.8;
    joint = lift+peg_insertion-nose;
    root = radius+0.8*lift/(peg_insertion-nose);
    translate([station.x,station.y,floor_z]) {
        rotate_extrude() polygon(concat(
            [[0,-eps],[root+0.45,-eps],[root+0.45,0],[root+0.12,0.12],[radius,lift]],
            [for(a=[0:10:90]) [shoulder-nose+nose*cos(a),joint+nose*sin(a)]],
            [[0,lift+peg_insertion]]));
        for(a=[90,210,330]) rotate([0,0,a]) translate([0,0,-4.4]) heel_pad();
    }
}

module bearing_mount(base) {
    lift = axis_z-7.2;
    translate([0,0,lift]) hinge(base);
    pitch = (27+0.55)/5;
    for(i=base ? [0,2,4] : [1,3])
        yz_prism(-13.5+i*pitch,pitch-0.55)
            polygon([[-7.35,rail_height],[-4.15,0],[-3.2,0],[-3.2,lift-1+eps],
                     [-5.5,lift+0.3],[-7.35,lift+0.3]]);
    // Raked stops meet only beyond the level printing/resting position.
    for(x=[-8.8,8.8])
        yz_prism(x-1.7,3.4)
            polygon([[-7.35,rail_height],[-1.13,0],[-0.57,0.55],[-0.49,2.25],
                     [-5.95,3.85],[-7.35,3.85]]);
}

module storage_latch(base) {
    // The original latch profile sits at the same offset below the raised hinge.
    lift = axis_z-7.2;
    shift = case_y-17.8+25;
    translate([0,shift,lift]) if(base) spring_clip(); else catch_ridge();
    if(base)
        yz_prism(-3.53,7.06)
            polygon([[case_y-17.8+1.1,rail_height],[case_y-17.8-0.95,rail_height],
                     [case_y-17.8-2,rail_height+1.05],[case_y-17.8-2.035,lift+0.25],
                     [case_y-17.8+1.1,lift+0.5]]);
}

module saddle(x, radius, base) {
    thick = 3.2;
    free_radius = radius+(base ? 0.17 : 0.45);
    half_width = base ? radius+1.45 : radius*0.64;
    center_z = base ? shaft_z : 2*axis_z-shaft_z;
    yz_prism(x-thick/2,thick)
        difference() {
            translate([-half_width,floor_z-eps])
                square([2*half_width,center_z-1.05-floor_z+eps]);
            translate([0,center_z]) circle(r=free_radius);
        }
}

module packed_fixtures(base) {
    for(sign=[-1,1]) head_frame(sign) {
        saddle(-32,7.2,base);
        saddle(4,5.13,base);
        if(base) {
            // The flat hard back of each disc registers against this blade near
            // its top and bottom edges. Both tufts face away from the blade.
            yz_prism(25,7)
                polygon([[6.12,floor_z-eps],[10.5,floor_z-eps],[10.5,4.8],[7.12,10.2],
                         [7.12,shaft_z+7.85],[6.92,shaft_z+8.25],[6.32,shaft_z+8.25],
                         [6.12,shaft_z+7.85]]);
            // End play is taken at the heel face and the hard edge of the disc.
            translate([-39.1,-3.2,floor_z-eps]) cube([1.65,6.4,shaft_z-1-floor_z]);
            translate([37.55,2.4,floor_z-eps]) cube([3.15,3.25,shaft_z+0.8-floor_z]);
        }
    }
}

module leaf_storage(base) {
    station = base ? base_peg : lid_peg;
    union() {
        storage_shell(station);
        storage_station(station);
        bearing_mount(base);
        storage_latch(base);
        packed_fixtures(base);
    }
}

module open_lid() {
    mirror([0,1,0]) leaf_storage(false);
}

if(part=="base") leaf_storage(true);
else if(part=="lid") open_lid();
else if(part=="open" || part=="closed") {
    color("#54807c") leaf_storage(true);
    color("#9dbbb2") translate([0,0,axis_z]) rotate([part=="closed" ? 180 : 0,0,0])
        translate([0,0,-axis_z]) open_lid();
} else assert(false,str("Unknown part: ",part));
