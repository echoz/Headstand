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

// Each bank sweeps from the floor to the sidewall, widening at the two
// rigid ends. The end-wall cove turns across the leaf and joins both banks.
function unit(t) = min(1,max(0,t));
function ease(t) = let(v=unit(t)) v*v*(3-2*v);
function soft_join(a,b,r) =
    let(k=min(r,(a+b)/2)) k==0 ? 0 : max(a,b) + pow(max(0,k-abs(a-b)),2)/(4*k);

function bank_rise(x,y) =
    let(heel = ease((-x-14)/20), crown = ease((x-7)/19),
        toe = -6.4-4.8*heel-4.0*crown,
        // Roll the shoulder down at the entrance to each crown. The
        // matching return beside the snap gives its pocket a low spillway.
        spillway = 0.48 * exp(-pow((x-21.6)/4.9,2)) * ease((7.75-y)/2.8),
        side = 11.0 * (1-spillway) * pow(unit((y-toe)/(7.55-toe)),1.55),
        end = 10.8 * pow(unit((abs(x)-28.5)/9.65),2.3),
        // A broad heel seat returns under the inboard side of the heel.
        // Its open edge runs back to the central floor in a long curve.
        wrap = 10.8 * ease((-x-17)/18) * ease((y+11.3)/6.4),
        crown_wrap = 13 * ease((x-25)/12) * ease((y+6)/8),
        side_end = soft_join(side,max(end,crown_wrap),2.7))
    min(10.8,max(0,soft_join(side_end,wrap,2.4)-0.8));

// Roll the exposed lip of the shaft cradle into the bank. The short,
// axial stop at the very end of the heel retains its fitted end face.
function bank_height(x,y) =
    let(stock = floor_z + bank_rise(x,y) - 0.08,
        radius = lookup(x,[[-28,7.55],[0,5.65],[23,4.90]]),
        cup = axis_z-sqrt(max(0,radius*radius-y*y)),
        blend = ease((x+37.20)/0.85)*ease((23-x)/3),
        lip = 1.65,
        rounding = pow(max(0,lip-abs(stock-cup)),2)/(4*lip),
        rounded = min(stock,cup)-rounding)
    stock + blend*(rounded-stock);

// Flat-topped stock at the heel and crescent at the crown are subsequently
// dished to the hard parts of the brush. Bottom and outside edges overlap
// the existing deck and wall.
module bank_stock() {
    nx = 152;
    ny = 64;
    stride = ny+1;
    n = (nx+1)*stride;
    points = [for (i=[0:nx],j=[0:ny])
        let(x=-38.5+77*i/nx, y=-lane+(lane+8.1)*j/ny)
        [x,y,bank_height(x,y)]];
    rim = concat([for(i=[0:nx-1]) i*stride],
                 [for(j=[0:ny-1]) nx*stride+j],
                 [for(i=[nx:-1:1]) i*stride+ny],
                 [for(j=[ny:-1:1]) j]);
    lower = [for(k=rim) [points[k].x,points[k].y,floor_z-0.35]];
    faces = concat(
        [for(i=[0:nx-1],j=[0:ny-1]) each let(k=i*stride+j)
            [[k,k+1,k+stride+1],[k,k+stride+1,k+stride]]],
        [for(q=[0:len(rim)-1]) let(next=(q+1)%len(rim))
             [rim[q],rim[next],n+next,n+q]],
        [[for(q=[0:len(rim)-1]) n+q]]);
    polyhedron(concat(points,lower),faces,convexity=4);
}

module shaft_clearance() {
    // The heel and shaft lift out vertically from the lower half-round.
    for (section=[[-37.22,-28,7.55,7.55],[-28,0,7.55,5.65],[0,23,5.65,4.90]])
        translate([section[0],0,axis_z]) rotate([0,90,0])
            cylinder(h=section[1]-section[0],r1=section[2],r2=section[3],$fn=128);
}

module crown_clearance(front_lid) {
    // In axial section the rigid disc meets a rounded inside corner.
    // The cut widens toward the tufts so the soft ends remain unloaded.
    relief = front_lid ? 0.095 : 0;
    multmatrix([[1,0,0,0],[0,1,relief,-relief*4],[0,0,1,0],[0,0,0,1]])
        translate([28.5,0,axis_z]) rotate([-90,0,0]) rotate_extrude($fn=128)
            polygon(concat([[0,-19],[12.5,-19]],
                [for(i=[0:28]) let(t=i/28) [12.5-3.74*ease(t),-8+10.5*t]],
                [[8.76,5.75]],
                [for(a=[5:5:90]) [8.47+0.29*cos(a),5.75+0.29*sin(a)]],
                [[0,6.04]]));
}

module packing_bank(front_lid) {
    difference() {
        bank_stock();
        shaft_clearance();
        crown_clearance(front_lid);
    }
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
            intersection() {
                linear_extrude(height=axis_z) outline(wall-0.35);
                union() for(sign=[-1,1]) head_frame(sign) packing_bank(!base && sign==-1);
            }
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
