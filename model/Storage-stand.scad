// Print flat open. The crowns face inward in opposite directions along the case.
use <Folding-stand.scad>

part = "open"; // [open, closed, base, lid]

/* [Brush fit] */
peg_diameter = 5.6; // [4:0.2:6.2]
peg_insertion = 7; // [4:0.2:7.2]

/* [Hidden] */
$fn = 64;
eps = 0.025;
axis_z = 12.8;
case_y = -27.7;
length = 79.2;
width = 47.1;
corner = 2.4;
wall = 1.6;
floor_z = 2.0;
near_wall = case_y - width/2;
base_peg = [-10,case_y];
lid_peg = [10,case_y];
lane = 14.45;

assert(peg_diameter >= 4 && peg_diameter <= 6.2);
assert(peg_insertion >= 4 && peg_insertion <= 7.2);

module outline(inset=0) {
    translate([0,case_y]) offset(r=corner-inset)
        square([length-2*corner,width-2*corner],center=true);
}

// Local +Y points toward the hard backs, away from the tufts.
module head_frame(sign) {
    translate([0,case_y+sign*lane,0])
        rotate([0,0,sign==1 ? 0 : 180]) children();
}

module sole_slot(x, y, length, diameter) {
    hull() for(dy=[-length/2,length/2])
        translate([x,y+dy,-eps]) cylinder(d=diameter,h=floor_z+2*eps);
}

module water_passages(station) {
    // Short through-slots beneath the hollow heel also cross its seating rim.
    for(sign=[-1,1])
        sole_slot(station.x,station.y+sign*6.05,5.5,2);
    for(sign=[-1,1]) head_frame(sign)
        for(x=[26,32]) sole_slot(x,-12,5,2);

    // Shallow channels across the sole drain on a level counter. The narrow
    // roofs bridge between solid bed-contact areas with the supports off.
    for(x=[station.x,-32,-26,26,32])
        translate([x,case_y,0]) hull()
            for(level=[[-eps,3.4],[1,1.4]])
                translate([0,0,level.x]) linear_extrude(height=eps)
                    square([level.y,width+1],center=true);
}

module storage_station(station) {
    radius = peg_diameter/2;
    shoulder = radius-0.8;
    nose = min(1.2,shoulder-0.45);
    translate([station.x,station.y,floor_z]) rotate_extrude()
        polygon(concat([[0,-eps],[radius,-eps],[radius,0]],
            [for(a=[0:10:90])
                [shoulder-nose+nose*cos(a),peg_insertion-nose+nose*sin(a)]],
            [[0,peg_insertion]]));
}

module shaft_fillet(section) {
    // A changing 45-degree fillet follows the shaft taper along the wall.
    // At the crown it falls below the rigid disc, leaving the tuft bay clear.
    wall_y = width/2-wall-lane+eps;
    yz_prism(section.x,eps)
        intersection() {
            polygon([[floor_z-section.y,floor_z-eps],[wall_y,floor_z-eps],
                     [wall_y,wall_y+section.y]]);
            translate([-10,0]) square([20,axis_z]);
        }
}

module packing_wall(front_lid) {
    fillet = [[-37,2.06],[-28,2.06],[0,4.90],[18,5.55],[23,0.75],
              [28.5,-1.60],[34,0.75],[37,2.06]];
    difference() {
        for(i=[0:len(fillet)-2]) hull() {
            shaft_fillet(fillet[i]);
            shaft_fillet(fillet[i+1]);
        }
        translate([28.5,6.1,axis_z]) rotate([90,0,0])
            cylinder(r=8.8,h=12);
    }

    // The short end wall cups the last 4 mm of the rigid heel. The half-round
    // opening lifts straight out when the matching half of the case is open.
    difference() {
        linear_extrude(height=axis_z)
            hull() {
                translate([-38.4,-8.0]) square([0.5,15.6]);
                translate([-36.9,-6.7]) circle(r=1.25);
                translate([-34.7,-4.8]) circle(r=1.3);
                translate([-34.7,6.2]) circle(r=1.3);
            }
        translate([-37.20,0,axis_z])
            rotate([0,90,0]) cylinder(r=7.55,h=5);
    }

    // Flare the corner inward against the flat disc back. The adjacent end
    // face limits end play on the rigid disc rather than on the bristles.
    // The front lip travels inward as it closes. Relieve its entrance while
    // keeping the close fit against the upper edge of the rigid disc back.
    for(i=[0,1]) hull() {
        for(j=[i,i+1]) {
            z = [0,4.5,axis_z-eps][j];
            back_y = front_lid && j==2 ? 6.85 : 6.04;
            translate([0,0,z]) linear_extrude(height=eps) polygon([
                [16,7.55],[22,back_y],[37.5,back_y],[38.05,7.55]
            ]);
        }
    }
    linear_extrude(height=axis_z) polygon([
        [37.25,6.9],[37.25,1.8],[38.05,0],[38.05,7.55],[36.9,7.55]
    ]);
}

module shell(base,station) {
    difference() {
        union() {
            difference() {
                linear_extrude(height=axis_z) outline();
                translate([0,0,floor_z]) linear_extrude(height=axis_z) outline(wall);
            }
            for(sign=[-1,1]) head_frame(sign) packing_wall(!base && sign==-1);
            storage_station(station);
        }
        water_passages(station);
    }
}

module bearing_mount(base) {
    lift = axis_z-7.2;
    translate([0,0,lift]) hinge(base);
    pitch = (27+0.55)/5;
    for(i=base ? [0,2,4] : [1,3])
        yz_prism(-13.5+i*pitch,pitch-0.55)
            polygon([[-7.35,1],[-4.25,0],[-3.2,0],[-3.2,lift-1+eps],
                     [-5.5,lift+0.3],[-7.35,lift+0.3]]);
    // The raked faces meet only beyond the level printing/resting position.
    for(x=[-8.8,8.8])
        yz_prism(x-1.7,3.4)
            polygon([[-7.35,1],[-1.13,0],[-0.57,0.55],[-0.49,2.25],
                     [-5.95,3.85],[-7.35,3.85]]);
}

module storage_latch(base) {
    lift = axis_z-7.2;
    translate([0,near_wall+25,lift]) if(base) spring_clip(); else catch_ridge();
    if(base)
        yz_prism(-3.53,7.06)
            polygon([[near_wall+1.1,0],[near_wall-0.95,0],[near_wall-2,1.05],
                     [near_wall-2.035,lift+0.25],[near_wall+1.1,lift+0.5]]);
}

module leaf_storage(base) {
    union() {
        shell(base,base ? base_peg : lid_peg);
        bearing_mount(base);
        storage_latch(base);
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
