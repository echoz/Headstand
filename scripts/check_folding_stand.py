"""Check the print-in-place stand in its delivered, flat printing pose."""

import argparse
from pathlib import Path

from manifold3d import CrossSection, Manifold

from check_compact_stand import support_margin
from check_meshes import EXPORTS, VOLUME_TOLERANCE, read_mesh, require


PIVOT_Z = 8.2
EYE_CENTERS = (-5.51, 5.51)
HEEL_SEAT = 3.8
PEG_INSERTION = 7.0
MIN_PRINT_GAP = 0.4
AREA_TOLERANCE = 0.001  # Square millimeters.


def read_leaves(path):
    assembly, count = read_mesh(path)
    leaves = assembly.decompose()
    require(len(leaves) == 2, f"Expected two watertight leaves, found {len(leaves)} connected components")
    require(all(leaf.volume() > 0 for leaf in leaves), "Both leaves must have positive volume")
    print(f"{path.name}: {count} facets, two watertight leaves")
    return sorted(leaves, key=lambda leaf: leaf.bounding_box()[1])


def check_counter_support(leaf, station):
    require(abs(leaf.bounding_box()[2]) < 0.005, f"Leaf at {station} does not sit at Z=0")
    # The STL transform can put a nominal Z=0 face a fraction of a micron above zero.
    contact = leaf.slice(0.005)
    # Hinge stop webs can add contact outside the three rails beneath the deck.
    rail_region = CrossSection.square((21, 20), center=True).translate((0, station[1]))
    rails = (contact ^ rail_region).decompose()
    require(len(rails) == 3, f"Leaf at {station} needs three independent counter rails")
    require(all(rail.area() > 40 for rail in rails), f"Leaf at {station} lacks a broad rail contact")
    pad = CrossSection.circle(0.25, 24)
    for y in (station[1] - 8, station[1], station[1] + 8):
        witnesses = [pad.translate((x, y)) for x in (-10, 10)]
        require(any(all((point - rail).area() < AREA_TOLERANCE for point in witnesses) for rail in rails),
                f"Leaf at {station} lacks a full-width rail at Y={y:g}")
    require(len((leaf.slice(0.95) ^ rail_region).decompose()) == 3,
            f"Leaf at {station} lost the 1 mm underside lift")
    require(support_margin(contact, station) > 2, f"Peg at {station} is too close to a tipping edge")


def check_head_mount(leaf, station):
    heel = CrossSection.circle(7.2, 72).translate(station)
    inner_heel = CrossSection.circle(4.5, 72).translate(station)
    contacts = leaf.slice(HEEL_SEAT - 0.01) ^ (heel - inner_heel)
    require(len(contacts.decompose()) == 3, f"Heel at {station} needs three independent supports")
    require(support_margin(contacts, station) > 2, f"Heel at {station} cannot carry a centered head")

    peg_start = leaf.slice(HEEL_SEAT + 0.01) ^ heel
    minimum_peg = CrossSection.circle(2.73, 72).translate(station)
    maximum_peg = CrossSection.circle(2.85, 72).translate(station)
    require((minimum_peg - peg_start).area() < AREA_TOLERANCE and
            (peg_start - maximum_peg).area() < AREA_TOLERANCE,
            f"Peg at {station} falls outside the nominal 5.6 mm seat diameter")
    near_tip = leaf.slice(HEEL_SEAT + PEG_INSERTION - 0.1) ^ heel
    require(near_tip.area() > 5, f"Peg at {station} loses its engagement before the nominal tip")
    above_tip = leaf.slice(HEEL_SEAT + PEG_INSERTION + 0.05) ^ heel
    require(above_tip.is_empty(), f"Peg at {station} exceeds the nominal insertion depth")

    # A straight 6.2 mm cavity represents a seated gauge, with the real head profile unmeasured.
    gauge_rim = (heel - CrossSection.circle(3.1, 72).translate(station)).extrude(PEG_INSERTION + 0.1)
    collision = leaf ^ gauge_rim.translate((0, 0, HEEL_SEAT + 0.005))
    require(collision.volume() < VOLUME_TOLERANCE, f"Rigid geometry fouls the seated heel gauge at {station}")


def check_drainage(leaf, station):
    x, y = station
    probe_height = 2.98
    below_deck = leaf.slice(probe_height).offset(0.25)
    probe = CrossSection.circle(0.12, 24)
    for side in (-1, 1):
        inlet_x = x + side * 5
        outlet_x = side * 18
        left = min(inlet_x, outlet_x) - 0.2
        lane = CrossSection.square((abs(outlet_x - inlet_x) + 0.4, 3)).translate((left, y - 1.5))
        inlet = probe.translate((inlet_x, y))
        outlet = probe.translate((outlet_x, y))
        passages = (lane - below_deck).decompose()
        require(any((passage ^ inlet).area() > 0.98 * probe.area() and
                    (passage ^ outlet).area() > 0.98 * probe.area() for passage in passages),
                f"Heel at {station} cannot drain below its deck toward X={outlet_x}")
        inlet_floor = leaf.ray_cast((inlet_x, y, probe_height), (inlet_x, y, 1.5))
        wall_x = side * 15.2
        outlet_floor = leaf.ray_cast((wall_x, y, probe_height), (wall_x, y, 1.5))
        require(inlet_floor and outlet_floor and
                (outlet_floor[0].distance - inlet_floor[0].distance) * (probe_height - 1.5) > 0.1,
                f"Drain floor at {station} does not fall toward X={outlet_x}")


def has_closed_bore(section):
    pivot = (-PIVOT_Z, 0)
    window = CrossSection.square((14, 14), center=True).translate(pivot)
    interior = window.offset(-0.1)
    axis = CrossSection.circle(0.25, 24).translate(pivot)
    return any((axis - void).area() < AREA_TOLERANCE and (void - interior).area() < AREA_TOLERANCE
               for void in (window - section).decompose())


def axle_cylinder(start, length, radius):
    return (Manifold.cylinder(length, radius, circular_segments=72)
            .rotate((0, 90, 0)).translate((start, 0, PIVOT_Z)))


def check_hinge(fixed, moving):
    axle_core = axle_cylinder(-11.02, 22.04, 1.20)
    require((axle_core - fixed).volume() < VOLUME_TOLERANCE,
            "No continuous integral axle through both bearings and their anchors")

    # Rotate onto the slicing plane so section X becomes minus world Z, section Y stays world Y.
    bearing = moving.rotate((0, -90, 0))
    bore = CrossSection.circle(2.08, 72).translate((-PIVOT_Z, 0))
    for center in EYE_CENTERS:
        for x in (center - 2, center, center + 2):
            section = bearing.slice(x)
            require(has_closed_bore(section), f"Bearing lacks a closed loop at X={x:.2f}")
            require((section ^ bore).area() < AREA_TOLERANCE, f"Bearing bore obstructed at X={x:.2f}")

    # Each eye must meet an anchor at either axial limit, inside the hinge barrel.
    for direction in (-1, 1):
        overlap = fixed ^ moving.translate((direction * 0.8, 0, 0))
        for center in EYE_CENTERS:
            shoulder_x = center + direction * 3.03
            shoulder = axle_cylinder(shoulder_x - 0.3, 0.6, 3.55)
            require((overlap ^ shoulder).volume() > 0.05,
                    f"Bearing at X={center:g} lacks an axial stop toward {direction:+d}X")
    print("Continuous axle through two closed bearing eyes, with axial retention at all four shoulders")


def swing(leaf, degrees):
    return leaf.translate((0, 0, -PIVOT_Z)).rotate((degrees, 0, 0)).translate((0, 0, PIVOT_Z))


def check_opening_stops(fixed, moving):
    short_of_stop = fixed ^ swing(moving, -2)
    require(short_of_stop.volume() < VOLUME_TOLERANCE, "Opening stops engage before allowed print play")
    overtravel = fixed ^ swing(moving, -6)
    for x in (-8.8, 8.8):
        stop = Manifold.cube((4, 4, 2.5)).translate((x - 2, -2, 0))
        require((overtravel ^ stop).volume() > 0.05, f"Solid opening stop missing at X={x:g}")
    print("Both opening stops prevent 6° of overtravel from flat")


def check_motion(fixed, moving):
    latch_region = Manifold.cube((9, 3.5, 5)).translate((-4.5, -28, 8))
    latch_engaged = False
    angles = sorted(set(range(0, 181, 5)) | {177 + step / 4 for step in range(12)})
    for angle in angles:
        overlap = fixed ^ swing(moving, angle)
        if overlap.volume() > VOLUME_TOLERANCE:
            require(177 <= angle < 180 and (overlap - latch_region).volume() < VOLUME_TOLERANCE,
                    f"Rigid geometry interferes at {angle:g}° from flat")
            latch_engaged = True
    require(latch_engaged, "No front catch engagement in the final 3° of closure")
    print(f"Closing sweep at {len(angles)} angles clears the pegs and leaves, with contact at the front catch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesh", nargs="?", type=Path, default=EXPORTS / "Folding-stand.stl")
    args = parser.parse_args()
    fixed, moving = read_leaves(args.mesh)
    gap = fixed.min_gap(moving, 1)
    require(gap >= MIN_PRINT_GAP, f"Flat print gap is only {gap:.3f} mm")
    print(f"Minimum gap between printed leaves: {gap:.3f} mm")
    check_hinge(fixed, moving)
    for leaf, station in ((fixed, (-4.2, -14)), (moving, (4.2, 14))):
        check_counter_support(leaf, station)
        check_head_mount(leaf, station)
        check_drainage(leaf, station)
    print("Both leaves sit on three coplanar rails and present upright pegs on three-point heel seats")
    print("Each heel has a below-deck drain path to both side outlets")
    check_opening_stops(fixed, moving)
    check_motion(fixed, moving)


if __name__ == "__main__":
    main()
