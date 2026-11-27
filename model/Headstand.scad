// Headstand. Millimetres. Both printable shells sit exterior face down.
// Both parts point +X to the bristles. The hinge is on +Y for the tray
// and -Y for the printed lid. The open view translates the printed lid.
part = "open"; // [open, closed, tray, lid, sample]

/* [Brush and socket fit] */
head_length = 74;
crown_width = 17;
heel_diameter = 14.4;
shank_diameter = 10.4;
socket_bore = 15.6;
socket_depth = 10;
socket_lip_flare = 0.65;

/* [Case and hinge] */
end_clearance = 4; // total axial allowance
lane_clearance = 1.8; // total width allowance per crown
crown_swing_clearance = 1.2; // local outward bow of the latch-side wall
wall = 1.8;
divider = 1.6;
shell_height = 16;
floor_thickness = 2.4;
pin_diameter = 1.75;
pin_clearance = 0.5; // diametral circular clearance
knuckle_gap = 0.5;

/* [Hidden] */
$fn = 72;
eps = 0.04;
lane_width = crown_width + lane_clearance;
length = head_length + end_clearance + 2*wall;
width = 2*lane_width + divider + 2*wall;
lane_y = (lane_width + divider)/2;
pivot_y = width/2 + 3.2;
corner_r = 5.5;
seat_z = floor_thickness + 0.8;
socket_y = 6;
socket_xs = [-15,8];
socket_radius = socket_bore/2;
socket_top = seat_z + socket_depth;
heel_x = -head_length/2 + 5;
shank_x = 0;
shaft_axis_z = floor_thickness + 0.75 + heel_diameter/2;
knuckle_r = 2.75;
hinge_span = length-10;
knuckle_length = (hinge_span-4*knuckle_gap)/5;
drain_width = 4.4;
drain_grade = 0.052;

assert(socket_bore > 6 && socket_top < shell_height);
assert(socket_radius+socket_lip_flare+0.8 <= socket_radius+wall);
assert(socket_xs[1]-socket_xs[0] > socket_bore+2*wall);
assert(socket_y+socket_radius+wall < width/2-wall);
assert(knuckle_r > (pin_diameter+pin_clearance)/sqrt(2)+0.8);
assert(2*shell_height-socket_top > shaft_axis_z + shank_diameter/2);
assert(floor_thickness - drain_grade*(width/2-socket_y+socket_radius) > 0.8);

module shell_outline(inset,crown_bow) {
    r=corner_r-inset;
    if (crown_bow) {
        // The moving front wall must pass the outside bristles on its arc.
        // A short bow keeps full wall thickness and leaves the latch straight.
        front=-width/2+corner_r;
        hull() for (center=[
            [head_length/2-24,front+0.4],
            [head_length/2-18,front-crown_swing_clearance],
            [length/2-corner_r,front-crown_swing_clearance],
            [length/2-corner_r,front+2]
        ]) translate(center) circle(r=r);
    } else {
        offset(r=r) square([length-2*corner_r,width-2*corner_r],center=true);
    }
}

module shell() {
    bevel = 0.8;
    difference() {
        union() for (bow=[false,true]) hull() {
            linear_extrude(height=eps) shell_outline(bevel,bow);
            translate([0,0,bevel]) linear_extrude(height=shell_height-bevel)
                shell_outline(0,bow);
        }
        translate([0,0,floor_thickness]) linear_extrude(height=shell_height)
            union() for (bow=[false,true]) shell_outline(wall,bow);
    }
}

// Extrude a profile drawn in Y,Z along X.
module yz_prism(x0,span) {
    translate([x0,0,0])
        multmatrix([[0,0,1,0],[1,0,0,0],[0,1,0,0],[0,0,0,1]])
            linear_extrude(height=span) children();
}

module knuckle(index) {
    x0 = -hinge_span/2 + index*(knuckle_length+knuckle_gap);
    bore_r = (pin_diameter+pin_clearance)/2;
    yz_prism(x0,knuckle_length)
        difference() {
            hull() {
                translate([pivot_y,shell_height]) circle(r=knuckle_r);
                // A diagonal web grows the barrel from the sidewall.
                translate([width/2-0.6,shell_height-8.2]) square([0.6,6.3]);
            }
            // The circular pin fits the lower arc; a 45-degree roof avoids a flat bridge.
            translate([pivot_y,shell_height])
                hull() {
                    circle(r=bore_r);
                    polygon([[-bore_r/sqrt(2),bore_r/sqrt(2)],
                             [0,bore_r*sqrt(2)],[bore_r/sqrt(2),bore_r/sqrt(2)]]);
                }
        }
}

module hinge_hardware(indices) {
    for (i=indices) knuckle(i);
    // Raised faces meet on the open hinge centre plane. Paired undercuts
    // leave a 4 mm-wide passage at sink level, clear to both ends of the hinge.
    for (x=[-length/2+10,length/2-10])
        yz_prism(x-3.2,6.4)
            polygon([[width/2-1.2,0],[pivot_y-2.4,0],[pivot_y-2,0.4],
                     [pivot_y-2,2.3],[pivot_y,4.3],[pivot_y,5.5],
                     [width/2-0.6,6.5],[width/2-1.2,6.5]]);
}

module cradle(x,d) {
    span=3.6;
    for (yc=[-lane_y,lane_y])
        yz_prism(x-span/2,span)
            difference() {
                translate([yc-lane_width/2-eps,floor_thickness-eps])
                    square([lane_width+2*eps,shaft_axis_z-floor_thickness-1.3]);
                translate([yc,shaft_axis_z]) circle(d=d+0.5);
            }
}

// Front latch profiles are measured outward from the front sidewall.
module front_profile(span,points) {
    yz_prism(-span/2,span)
        polygon([for(p=points) [-width/2-p[0],p[1]]]);
}

module latch_tongue() {
    h=shell_height;
    // Free beam, 1.6 mm thick, with a cammed inward tooth and an external finger lip.
    front_profile(13,[
        [-1.1,0],[3.1,0],[3.65,0.55],[3.65,h+5.7],
        [4.35,h+6.4],[4.35,h+7.4],[2.05,h+7.4],
        [0.35,h+5.3],[2.05,h+4.25],[2.05,5.4],[-0.4,3.5],[-1.1,3.5]
    ]);
}

module latch_ridge() {
    h=shell_height;
    front_profile(14,[
        [-0.4,h-5.2],[0,h-5.2],[1.45,h-4.3],
        [1.45,h-3.65],[0,h-1.9],[-0.4,h-1.9]
    ]);
}

// A tapered floor groove leads each bristle bay through the crown-end wall.
// The peaked port roof prints without a horizontal span across the opening.
module crown_drain(yc) {
    hull()
        for (outlet=[false,true]) {
            x=outlet ? length/2+eps : head_length/2-13;
            z=outlet ? floor_thickness-0.8 : floor_thickness+eps;
            yz_prism(x,eps) translate([yc,z])
                polygon([[-2.2,0],[2.2,0],[2.2,1.8],[0,4],[-2.2,1.8]]);
        }
}

module crown_separator() {
    // The tall portion stays between the bristles throughout the hinge sweep.
    start=head_length/2-19.5;
    end=length/2-wall-0.9;
    top=2*shell_height-floor_thickness-1.8;
    translate([0,divider/2,0]) rotate([90,0,0]) linear_extrude(height=divider)
        polygon([[start,shell_height-0.5],[end,shell_height-0.5],
                 [end,top-1.2],[end-1.2,top],[start+2.0,top],[start,top-2.0]]);
}

module travel_tray() {
    union() {
        difference() {
            shell();
            for (yc=[-lane_y,lane_y]) crown_drain(yc);
        }
        translate([-length/2+wall-eps,-divider/2,floor_thickness-eps])
            cube([length-2*wall+2*eps,divider,shell_height-floor_thickness-0.16]);
        crown_separator();
        cradle(heel_x,heel_diameter);
        cradle(shank_x,shank_diameter);
        hinge_hardware([0,2,4]);
        latch_tongue();
    }
}

module heel_keeper() {
    for (yc=[-lane_y,lane_y])
        yz_prism(heel_x-2,4)
            difference() {
                translate([yc-lane_width/2-eps,floor_thickness-eps])
                    square([lane_width+2*eps,shell_height-0.65-floor_thickness]);
                translate([yc,2*shell_height-shaft_axis_z]) circle(d=heel_diameter+3.2);
            }
}

module vent_slots() {
    for(yc=[-lane_y,lane_y], offset_y=[-4.1,0,4.1])
        hull()
            for (tip=[head_length/2-15,head_length/2-3.6])
                translate([tip,yc+offset_y,-eps]) cylinder(d=2.05,h=floor_thickness+2*eps);
}

// Remove a shallow plane from the socket floor, continuing downhill to the
// wall. The wider mouth at the collar collects water from the circular seat.
module socket_drain(x) {
    y_start = socket_y-socket_radius-0.2;
    y_exit = width/2+0.4;
    z_start = floor_thickness-0.06;
    z_exit = z_start-drain_grade*(y_exit-y_start);
    intersection() {
        yz_prism(x-socket_radius-1,2*socket_radius+2)
            polygon([[y_start,z_start],[y_exit,z_exit],[y_exit,5.8],[y_start,5.8]]);
        union() {
            translate([x,socket_y,0]) cylinder(r=socket_radius+eps,h=6);
            hull() {
                translate([x-(socket_radius-1.2),socket_y,0])
                    cube([2*(socket_radius-1.2),0.1,6]);
                translate([x-drain_width/2,socket_y+socket_radius+wall,0])
                    cube([drain_width,0.1,6]);
            }
            translate([x-drain_width/2,socket_y,0])
                cube([drain_width,y_exit-socket_y+eps,6]);
        }
    }
}

module collar(x) {
    // Flare the inner lip to guide a wet heel into the straight bore.
    translate([x,socket_y,floor_thickness-eps])
        difference() {
            cylinder(r=socket_radius+wall,h=socket_top-floor_thickness+eps);
            translate([0,0,-eps])
                cylinder(r=socket_radius,h=socket_top-floor_thickness+3*eps);
            translate([0,0,socket_top-floor_thickness-1.1+eps])
                cylinder(r1=socket_radius,r2=socket_radius+socket_lip_flare,
                         h=1.1+eps);
        }
}

module socket_feet(x) {
    // Three small radial ledges carry the heel above the drainage plane.
    for (a=[-90,30,150])
        translate([x,socket_y,0]) rotate([0,0,a])
            translate([socket_radius-3.4,-1.25,1.3])
                cube([3.45,2.5,seat_z-1.3]);
}

// Construct the fittings in tray plan coordinates to maintain registration.
module lid_in_tray_plan(with_hardware=true) {
    union() {
        difference() {
            union() {
                shell();
                if (with_hardware) hinge_hardware([1,3]);
                latch_ridge();
                heel_keeper();
                for (x=socket_xs) collar(x);
            }
            vent_slots();
            for (x=socket_xs) socket_drain(x);
        }
        for (x=socket_xs) socket_feet(x);
    }
}

module stand_lid() {
    mirror([0,1,0]) lid_in_tray_plan();
}

module socket_sample() {
    // Crop the actual lid so the sample reproduces its ledges, floor and outlet.
    x=socket_xs[1];
    r=socket_radius+wall+1.0;
    mirror([0,1,0]) intersection() {
        lid_in_tray_plan(with_hardware=false);
        translate([x-r,socket_y-r,-eps])
            cube([2*r,width/2-socket_y+r+eps,shell_height+2*eps]);
    }
}

if (part=="tray") travel_tray();
else if (part=="lid") stand_lid();
else if (part=="sample") socket_sample();
else if (part=="open" || part=="closed") {
    color("#5d8388") travel_tray();
    color("#ddaa80")
        if (part=="open") translate([0,2*pivot_y,0]) stand_lid();
        else translate([0,0,2*shell_height]) rotate([180,0,0]) stand_lid();
}
else assert(false,str("Unknown part: ",part));
