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
lane = 14.45;
latch_x = -13;

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

module water_passages() {
    slot_radius = 1.2;
    heel_inlet = peg_diameter/2 + 0.04;
    crown_end = 26;
    outlet_start = crown_end-slot_radius;
    for(turn=[0,180]) translate([0,case_y,0]) rotate([0,0,turn]) {
        // The same opening crosses the upright heel rim and the packed tuft bay.
        hull() for(x=[heel_inlet+slot_radius,outlet_start])
            translate([x,0,-eps]) cylinder(r=slot_radius,h=floor_z+2*eps);

        // The counter closes the bottom of this passage. Its sloped sides leave
        // only a 1.2 mm bridge at the roof of the outlet.
        yz_prism(outlet_start,length/2-outlet_start+eps)
            polygon([[-1.6-eps,-eps],[1.6+eps,-eps],[0.6,1],[-0.6,1]]);
    }
}

module storage_station() {
    radius = peg_diameter/2;
    shoulder = radius-0.8;
    nose = min(1.2,shoulder-0.45);
    translate([0,case_y,floor_z]) rotate_extrude()
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

module shell(base) {
    pocket_half_width = base ? 7.6 : 8.4;
    pocket_inset = base ? 1.50 : 1.27;
    difference() {
        union() {
            difference() {
                linear_extrude(height=axis_z) outline();
                translate([0,0,floor_z]) linear_extrude(height=axis_z) outline(wall);
            }
            for(sign=[-1,1]) head_frame(sign) packing_wall(!base && sign==-1);
            storage_station();
        }
        water_passages();
        // Free the springs from the shaft fillet while preserving the outside skin
        // and the sloping brush support on the inboard side of the pocket.
        translate([latch_x-pocket_half_width,near_wall+pocket_inset,base ? floor_z : 5.8])
            cube([2*pocket_half_width,4.75-pocket_inset,axis_z]);
        if(base)
            translate([0,near_wall-0.35,axis_z]) scale([8.8,1.15,2.15]) sphere(r=1);
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

// Extrude an X,Z profile parallel to the front wall, easing the cam edges.
module latch_profile(inset, depth, points) {
    translate([latch_x,near_wall+inset+depth,0]) rotate([90,0,0])
        linear_extrude(height=depth)
            offset(r=0.18,$fn=24) offset(delta=-0.18) polygon(points);
}

module storage_latch(base) {
    if(base) {
        // The tines spread lengthwise, parallel to the shaft, as the keeper
        // passes between them. Both contact faces are ramps for pull-to-open.
        tine = [[2.49,floor_z-0.5],[6.16,floor_z-0.5],[6.16,2.01],[5.84,2.13],
                [5.59,2.33],[5.43,2.59],[5.35,2.93],[5.35,17.90],[4.95,18.30],[3.50,18.30],
                [1.90,16.70],[1.90,16.20],[3.30,14.80],
                [3.30,2.93],[3.22,2.59],[3.06,2.33],[2.81,2.13],[2.49,2.01]];
        for(side=[-1,1])
            latch_profile(2.35,1.35,[for(p=tine) [side*p.x,p.y]]);
    } else {
        // Closed Z coordinates make the 1.10 mm engagement at each tooth
        // explicit. The narrow rib joins the keeper to the lid floor and wall.
        keeper = [[-1.45,12.98],[1.45,12.98],[3.00,14.36],[3.00,14.66],
                  [1.02,16.64],[1.02,2*axis_z-floor_z+0.5],
                  [-1.02,2*axis_z-floor_z+0.5],[-1.02,16.64],[-3.00,14.66],[-3.00,14.36]];
        latch_profile(1.17,2.53,[for(p=keeper) [p.x,2*axis_z-p.y]]);
    }
}

module leaf_storage(base) {
    union() {
        shell(base);
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
