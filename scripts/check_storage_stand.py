"""Check the flat print and loaded motion of the two-head storage stand."""

import argparse
from dataclasses import dataclass
from itertools import product
from math import cos, radians, sin
from pathlib import Path

import numpy as np
from manifold3d import CrossSection, Error, Manifold

from check_compact_stand import support_margin
from check_folding_stand import (
    AREA_TOLERANCE, MIN_PRINT_GAP, PIVOT_Z as FOLDING_PIVOT_Z, check_hinge, read_leaves,
)
from check_meshes import EXPORTS, VOLUME_TOLERANCE, packed_heads, require

PIVOT = np.array((0, 0, 12.8))
STATIONS = ((-10, -27.7), (10, 27.7))
HEEL_HEIGHT = 2.0
PEG_DIAMETER = 5.6
PEG_INSERTION = 7.0
HINGE_RADIAL_PLAY = 0.55
HINGE_AXIAL_PLAY = 0.55
SHELL_FOOTPRINT = ((-39.6, -51.25), (39.6, -4.15))
PACKED_ENVELOPE = (80, 58, 26)


@dataclass(frozen=True)
class PackingPosition:
    center: tuple[float, float, float]
    yaw: float

    def place(self, piece, roll=0, shift=(0, 0, 0)):
        return self.move_in_lane(piece, (roll, 0, 0), (0, 0, 0)).translate(shift)

    def move_in_lane(self, piece, rotation, shift, pivot=(0, 0, 0)):
        pivot = np.asarray(pivot)
        return (piece.rotate((90, 0, 0)).translate(-pivot).rotate(rotation).translate(pivot + shift)
                .rotate((0, 0, self.yaw)).translate(self.center))


PACKING_POSITIONS = (
    PackingPosition((0, -13.25, 12.8), 0),
    PackingPosition((0, -42.15, 12.8), 180),
)


def swing(lid, pivot, degrees):
    return lid.translate(-pivot).rotate((degrees, 0, 0)).translate(pivot)


def check_flat_print(base, lid, stations):
    gap = base.min_gap(lid, 1)
    require(gap >= MIN_PRINT_GAP, f"Flat print gap is only {gap:.3f} mm")
    for leaf, station in zip((base, lid), stations):
        require(abs(leaf.bounding_box()[2]) < 0.005, f"Leaf at {station} does not sit at Z=0")
        contact = leaf.slice(0.005)
        require(contact.area() > 30, f"Leaf at {station} lacks usable flat contact")
        require(support_margin(contact, station) > 2,
                f"Peg at {station} is too close to a counter tipping edge")
    print(f"Flat print gap {gap:.3f} mm; both peg loads are inside their leaf's counter support")


def travel_gauge():
    gauges = packed_heads().decompose()
    require(len(gauges) == 2, "The existing storage gauge must provide an independent head for each lane")
    gauge = min(gauges, key=lambda solid: solid.bounding_box()[1]).translate((0, 10.2, 0))
    lower = np.array(gauge.bounding_box()[:3])
    upper = np.array(gauge.bounding_box()[3:])
    require(np.allclose(upper - lower, (74, 17, 23.55)),
            "Storage gauge no longer represents the 74 mm brush with a 17 × 22 mm crown")
    return gauge.translate((0, 0, -10.35))


def check_insertion(base, lid, gauge, placements):
    opened = base + lid
    heads = [placement.place(gauge) for placement in placements]
    height = max(1, opened.bounding_box()[5] - min(head.bounding_box()[2] for head in heads) + 1)
    # The gauge's local +Y becomes vertical in its side-facing packing position.
    sweep_vector = Manifold.cube((0.002, height, 0.002)).translate((-0.001, 0, -0.001))
    insertion_sweep = gauge.minkowski_sum(sweep_vector)
    require(insertion_sweep.status() == Error.NoError, "Could not sweep the head insertion gauge")
    for number, placement in enumerate(placements, 1):
        swept = placement.place(insertion_sweep)
        require((swept ^ opened).volume() < VOLUME_TOLERANCE,
                f"Head {number} cannot drop into or lift out of its lane with the stand open")
        other = heads[2 - number]
        require((swept ^ other).volume() < VOLUME_TOLERANCE,
                f"Head {number} cannot be removed while its neighbor is packed")
    print("Both heads can be inserted and removed vertically while the other head stays in its lane")


def check_packed_walls(closed, placement, number, wall_faces):
    yaw = radians(placement.yaw)
    along = np.array((cos(yaw), sin(yaw), 0))
    outside = np.array((-sin(yaw), cos(yaw), 0))
    up = np.array((0, 0, 1))
    crown = np.array(placement.center) + 28.5 * along - 9 * outside
    heel = np.array(placement.center) - 33 * along
    for name, location, end in (("crown", crown, along), ("heel", heel, -along)):
        # These locations leave the floor and roof vents clear. Horizontal
        # rays bracket the closing seam so each half provides a barrier.
        directions = (
            ("side", location - 4 * up, outside),
            ("side", location + 4 * up, outside),
            ("end", location - 4 * up, end),
            ("end", location + 4 * up, end),
            ("floor", location, -up),
            ("roof", location, up),
        )
        for face, start, direction in directions:
            hits = closed.ray_cast(start, start + 100 * direction)
            problem = f"Head {number} lacks an exterior {name} {face} barrier"
            require(len(hits) >= 2, problem)
            enter, leave = hits[-2:]
            axis = int(np.argmax(np.abs(direction)))
            face_limit = wall_faces[axis][int(direction[axis] > 0)]
            require(100 * (leave.distance - enter.distance) >= 0.5 and
                    abs(leave.position[axis] - face_limit) <= 1.25, problem)


def rounded_rectangle(bounds, radius):
    lower, upper = np.asarray(bounds)
    size = upper - lower - 2 * radius
    center = (lower + upper) / 2
    return CrossSection.square(size, center=True).offset(radius, circular_segments=64).translate(center)


def check_rectangular_shell(closed, bounds, wall_levels, hardware):
    lower, upper = np.asarray(bounds)
    tolerance = 0.08  # Clear of the polygonal outline and STL boundary.
    outline = CrossSection.square(upper - lower).translate(lower)
    bottom = closed.bounding_box()[2] - 1
    height = closed.bounding_box()[5] - bottom + 1
    rectangular_prism = outline.offset(tolerance).extrude(height).translate((0, 0, bottom))
    require((closed - (rectangular_prism + hardware)).volume() < VOLUME_TOLERANCE,
            "Shell projects outside the rectangular footprint beyond the hinge and catch")

    # The two contours bound the corner radius while requiring material right
    # along each straight wall. Floor ports and internal supports are out of band.
    maximum_outline = rounded_rectangle(bounds, 1).offset(tolerance)
    minimum_outline = rounded_rectangle(bounds, 2.5)
    perimeter = minimum_outline.offset(-tolerance) - minimum_outline.offset(-0.3)
    for level in wall_levels:
        shell = closed.slice(level)
        local_hardware = hardware.slice(level)
        require((shell - maximum_outline - local_hardware).area() < AREA_TOLERANCE,
                f"Exterior corners are too sharp at Z={level:g} mm")
        require((perimeter - shell - local_hardware).area() < AREA_TOLERANCE,
                f"Exterior does not have four straight walls with small corners at Z={level:g} mm")
    print("Four straight exterior walls and small corner radii on both halves, with local hinge and catch exceptions")


def check_freestanding_pegs(closed, footprint, stations):
    # Section the closed leaves below the peg tips. Count only contours well
    # inside the perimeter so wall-connected supports and hardware can vary.
    interior = rounded_rectangle(footprint, 2.5).offset(-0.2)
    for station, level in zip(stations, (5, 2 * PIVOT[2] - 5)):
        islands = [section for section in closed.slice(level).decompose()
                   if (section - interior).area() < AREA_TOLERANCE]
        peg = CrossSection.circle(0.1, 24).translate((station[0], -abs(station[1])))
        require(len(islands) == 1 and (peg - islands[0]).area() < AREA_TOLERANCE,
                f"Expected only the upright peg as a freestanding interior feature at Z={level:g} mm")
    print("Only the upright peg stands free of the walls on each leaf")


def check_enclosure(closed, heads, placements, envelope, footprint):
    lower = np.asarray(closed.bounding_box()[:3])
    upper = np.asarray(closed.bounding_box()[3:])
    dimensions = upper - lower
    require(np.all(dimensions <= envelope), f"Storage case exceeds the compact envelope: {dimensions}")
    hull = closed.hull()
    # Locate the barriers at the case walls, clear of local latch and hinge parts.
    wall_faces = (*zip(*footprint), (lower[2], upper[2]))
    for number, (head, placement) in enumerate(zip(heads, placements), 1):
        require((head - hull).volume() < VOLUME_TOLERANCE,
                f"Head {number} protrudes beyond the closed storage enclosure")
        check_packed_walls(closed, placement, number, wall_faces)
    print(f"Closed envelope {' × '.join(f'{d:.2f}' for d in dimensions)} mm; wall barriers surround both gauges")


def check_head_sweep(lid, pivot, head, number):
    bounds = head.bounding_box()
    far_y = max(abs(bounds[index] - pivot[1]) for index in (1, 4))
    far_z = max(abs(bounds[index] - pivot[2]) for index in (2, 5))
    radius = np.hypot(far_y, far_z)
    remaining = [(0, 180)]
    sampled_only = 0
    while remaining:
        start, end = remaining.pop()
        midpoint = (start + end) / 2
        # Inverse lid rotation can move any gauge point by at most this chord length.
        chord = 2 * radius * sin(radians(end - start) / 4)
        positioned = swing(lid, pivot, midpoint)
        if positioned.min_gap(head, chord + 0.0001) >= chord + 0.0001:
            continue
        overlap = (positioned ^ head).volume()
        require(overlap < VOLUME_TOLERANCE, f"Lid fouls head {number} at {midpoint:g}° ({overlap:.3f} mm³)")
        if end - start <= 0.0625:
            sampled_only += 1
        else:
            remaining.extend(((start, midpoint), (midpoint, end)))
    return sampled_only


def check_motion(base, lid, pivot, heads, latch_region):
    require((heads[0] ^ heads[1]).volume() < VOLUME_TOLERANCE, "Packed head gauges overlap one another")
    for number, head in enumerate(heads, 1):
        require((base ^ head).volume() < VOLUME_TOLERANCE,
                f"Head {number} intersects the tray in its packing position")

    angles = sorted(set(range(0, 181, 2)) | {177 + step / 4 for step in range(13)})
    latch_engaged = False
    for angle in angles:
        positioned = swing(lid, pivot, angle)
        for number, head in enumerate(heads, 1):
            overlap = (positioned ^ head).volume()
            require(overlap < VOLUME_TOLERANCE,
                    f"Lid fouls head {number} at {angle:g}° ({overlap:.3f} mm³)")
        overlap = base ^ positioned
        if overlap.volume() > VOLUME_TOLERANCE:
            require(165 < angle < 180 and (overlap - latch_region).volume() < VOLUME_TOLERANCE,
                    f"Rigid leaves interfere at {angle:g}°")
            latch_engaged = True
    require(latch_engaged, "Front catch never engages during the sampled closing path")
    sampled_only = sum(check_head_sweep(lid, pivot, head, number)
                       for number, head in enumerate(heads, 1))
    print(f"Loaded closing sweep checked at {len(angles)} angles, with contact limited to the front catch")
    if sampled_only:
        print(f"Head sweep clearance proved between samples except for {sampled_only} intervals under 0.0625°")
    else:
        print("Head clearance is bounded across every interval of the closing sweep")


def check_latch_retention(base, lid, pivot, latch_region):
    fixed_latch = base ^ latch_region
    slip = np.array((0, 0.38, 0.38))
    fractions = [step / 20 for step in range(21)]
    # Slide in the hinge play while closed, swing 2°, then restore the axis and keep opening.
    opening_path = ([(180, fraction * slip) for fraction in fractions]
                    + [(180 - step / 20, slip) for step in range(1, 41)]
                    + [(178, fraction * slip) for fraction in reversed(fractions)]
                    + [(178 - step / 4, (0, 0, 0)) for step in range(1, 53)])
    require(any((fixed_latch ^ swing(lid, pivot, angle).translate(offset)).volume() > VOLUME_TOLERANCE
                for angle, offset in opening_path),
            "Rigid latch can open after the hinge shifts +0.38 mm in Y and Z")

    # Each eroded patch is present for every translation in a Y/Z cell and
    # across the axial play interval. This bound keeps the hinge axes parallel.
    cell = 0.1
    half = cell / 2
    extent = int(np.ceil(HINGE_RADIAL_PLAY / cell))
    coordinates = [index * cell for index in range(-extent, extent + 1)]
    offsets = [(0, y, z) for y in coordinates for z in coordinates
               if np.hypot(max(abs(y) - half, 0), max(abs(z) - half, 0)) <= HINGE_RADIAL_PLAY + 1e-9]
    kernel = Manifold.cube((2 * HINGE_AXIAL_PLAY, cell, cell), center=True)
    lower = np.asarray(latch_region.bounding_box()[:3]) - 1
    upper = np.asarray(latch_region.bounding_box()[3:]) + 1
    capture = Manifold.cube(upper - lower).translate(lower)
    for angle in np.arange(179.875, 165, -0.125):
        patch = swing(lid, pivot, angle) ^ capture
        eroded = patch.minkowski_difference(kernel)
        require(eroded.status() == Error.NoError, "Could not bound latch contact across hinge play")
        minimum_overlap = min((fixed_latch ^ eroded.translate(offset)).volume() for offset in offsets)
        if minimum_overlap > VOLUME_TOLERANCE:
            print(f"Latch at {angle:g}° retains at least {minimum_overlap:.3f} mm³ of overlap "
                  f"across {HINGE_RADIAL_PLAY:g} mm radial and ±{HINGE_AXIAL_PLAY:g} mm axial hinge play")
            return
    raise ValueError("No tested latch angle blocks rigid opening across the modeled radial and axial hinge play")


def bristle_tips(gauge):
    # Use the last 8 mm of the canonical 22 mm crown as the side-facing bristle-tip region.
    return gauge.trim_by_plane((0, 0, 1), 26.7 - 10.35 - 8)


def check_shaft_support(base, gauge, placements):
    heel_side = gauge.trim_by_plane((-1, 0, 0), 8)
    neck_side = (gauge.trim_by_plane((1, 0, 0), -8)
                 .trim_by_plane((-1, 0, 0), -19.5))
    tips = bristle_tips(gauge)
    for number, placement in enumerate(placements, 1):
        for region, piece in (("heel", heel_side), ("shaft", neck_side)):
            overlap = base ^ placement.place(piece, shift=(0, 0, -2))
            require(overlap.volume() > 0.05, f"Head {number} lacks {region} support within 2 mm")
        def lowered(distance):
            return placement.place(gauge, shift=(0, 0, -distance))

        distance = first_contact(base, lowered, [step / 5 for step in range(1, 11)])
        require(distance is not None, f"Head {number} lacks a seating stop")
        lowered_tips = placement.place(tips, shift=(0, 0, -distance))
        require(lowered_tips.min_gap(base, 0.02) >= 0.02,
                f"Head {number} meets the tray at its bristle tips under downward load")
    print("Each head has separated heel and shaft support with the bristles clear")


def first_contact(obstacles, body_at, distances):
    clear_distance = 0
    for distance in distances:
        if (obstacles ^ body_at(distance)).volume() < VOLUME_TOLERANCE:
            clear_distance = distance
            continue
        for _ in range(8):
            midpoint = (clear_distance + distance) / 2
            if (obstacles ^ body_at(midpoint)).volume() < VOLUME_TOLERANCE:
                clear_distance = midpoint
            else:
                distance = midpoint
        return distance
    return None


def check_transport_stop(shell, neighbor, neighbor_tips, gauge, tips, placement, number, motion, distances, poses):
    def body_at(distance):
        return placement.place(gauge, *poses(distance))

    distance = first_contact(shell, body_at, distances)
    require(distance is not None, f"Head {number} has no case stop during {motion} by {distances[-1]:g}")
    tip_probe = placement.place(tips, *poses(distance))
    require(tip_probe.min_gap(shell, 0.02) >= 0.02,
            f"Head {number} meets the case at its bristle tips during {motion} ({distance:.2f})")
    neighbor_distance = first_contact(neighbor, body_at, [step for step in distances if step < distance] + [distance])
    if neighbor_distance is not None:
        tip_probe = placement.place(tips, *poses(neighbor_distance))
        require(tip_probe.min_gap(neighbor, 0.02) >= 0.02 and
                body_at(neighbor_distance).min_gap(neighbor_tips, 0.02) >= 0.02,
                f"Head {number} meets its neighbor at its bristle tips during {motion} ({neighbor_distance:.2f})")
    return distance, neighbor_distance


def check_transport(closed, gauge, placements):
    heads = [placement.place(gauge) for placement in placements]
    tips = bristle_tips(gauge)
    for number, placement in enumerate(placements, 1):
        neighbor = heads[2 - number]
        neighbor_tips = placements[2 - number].place(tips)
        translation_stops = []
        neighbor_contacts = []
        for axis, name in zip(np.eye(3), ("X", "Y", "Z")):
            for direction in (-1, 1):
                motion = f"{direction:+d}{name} translation (mm)"
                distance, neighbor_distance = check_transport_stop(
                    closed, neighbor, neighbor_tips, gauge, tips, placement, number, motion,
                    [step / 5 for step in range(1, 21)],
                    lambda distance: (0, direction * distance * axis),
                )
                translation_stops.append(distance)
                if neighbor_distance is not None:
                    neighbor_contacts.append(f"{motion} at {neighbor_distance:.2f}")
        roll_stops = []
        for direction in (-1, 1):
            motion = f"{direction:+d} shaft roll (degrees)"
            distance, neighbor_distance = check_transport_stop(
                closed, neighbor, neighbor_tips, gauge, tips, placement, number, motion,
                list(range(1, 31)), lambda distance: (direction * distance, (0, 0, 0)),
            )
            roll_stops.append(distance)
            if neighbor_distance is not None:
                neighbor_contacts.append(f"{motion} at {neighbor_distance:.2f}")
        print(f"Head {number} stopped by {max(translation_stops):.2f} mm in all sampled translation directions; "
              f"shaft roll stops at {roll_stops[0]:.1f}° and {roll_stops[1]:.1f}°")
        for contact in neighbor_contacts:
            print(f"Head {number} can meet the other gauge before the case stop during {contact}")


def check_combined_transport(closed, gauge, placements):
    # A free hard body once let its upper bristle edge gouge the roof on this coupled path.
    shift = np.array((0.183, -0.190, 0.371))
    rotation = np.array((-5.234, -0.750, -0.483))
    fractions = [step / 20 for step in range(1, 21)]
    tips = bristle_tips(gauge)
    hard_body = gauge - tips
    for number, placement in enumerate(placements, 1):
        neighbor = placements[2 - number]
        neighbor_tips = neighbor.place(tips)
        rigid_obstacles = closed + neighbor.place(hard_body)
        for signs in product((-1, 1), repeat=3):
            # Angular axes reverse sign under a reflection that changes handedness.
            reflected_shift = shift * signs
            reflected_rotation = rotation * signs * np.prod(signs)

            def moved(piece, fraction):
                return placement.move_in_lane(piece, fraction * reflected_rotation, fraction * reflected_shift)

            stop = first_contact(rigid_obstacles, lambda fraction: moved(hard_body, fraction), fractions)
            travel = 1 if stop is None else stop
            for fraction in [step for step in fractions if step < travel] + [travel]:
                require(moved(tips, fraction).min_gap(rigid_obstacles, 0.02) >= 0.02 and
                        moved(gauge, fraction).min_gap(neighbor_tips, 0.02) >= 0.02,
                        f"Head {number} bristle contact on combined motion {signs} at {fraction:.3f} of path")
    print("No bristle contact before a rigid stop on 16 sampled combined-motion paths")


def check_heel_pivot_transport(closed, gauge, placements):
    # The heel occupies the first 9 mm of the 74 mm gauge.
    heel = (-32.5, 0, 0)
    angles = [step / 10 for step in range(1, 101)]
    axial_travel = [step / 10 for step in range(1, 41)]
    tips = bristle_tips(gauge)
    hard_body = gauge - tips
    for number, placement in enumerate(placements, 1):
        neighbor = placements[2 - number]
        neighbor_tips = neighbor.place(tips)
        rigid_obstacles = closed + neighbor.place(hard_body)
        axial_offsets = [0]
        for direction in (-1, 1):
            def shifted(distance):
                return placement.move_in_lane(hard_body, (0, 0, 0), (direction * distance, 0, 0))

            travel = first_contact(rigid_obstacles, shifted, axial_travel)
            require(travel is not None, f"Head {number} has no rigid axial stop toward {direction:+d}X")
            axial_offsets.append(direction * travel / 2)

        # Pivot from the nominal seat and halfway into the available axial play on either side.
        for offset in axial_offsets:
            for direction in (-1, 1):
                def moved(piece, angle):
                    rotation = (0, 0, direction * angle)
                    return placement.move_in_lane(piece, rotation, (offset, 0, 0), pivot=heel)

                start = f"Head {number} at {offset:+.2f} mm axial offset during {direction:+d} heel-pivot yaw"
                stop = first_contact(rigid_obstacles, lambda angle: moved(hard_body, angle), angles)
                require(stop is not None, f"{start} has no rigid stop within {angles[-1]:g}°")
                for angle in [0] + [sample for sample in angles if sample < stop] + [stop]:
                    require(moved(tips, angle).min_gap(rigid_obstacles, 0.02) >= 0.02 and
                            moved(gauge, angle).min_gap(neighbor_tips, 0.02) >= 0.02,
                            f"{start} makes bristle contact at {angle:.2f}°")
    print("A rigid stop precedes bristle contact on 12 sampled heel-pivot yaw paths including axial play")


def check_upright_mount(leaf, station, heel_height, diameter, insertion):
    heel = CrossSection.circle(7.2, 72).translate(station)
    cavity = CrossSection.circle(3.1, 72).translate(station)
    contacts = leaf.slice(heel_height - 0.01) ^ (heel - cavity)
    require(contacts.area() > 1 and support_margin(contacts, station) > 2,
            f"Heel at {station} lacks a seat under its rim")

    # The floor slots may scallop the peg root. Measure the locating section above them.
    peg = leaf.slice(heel_height + 0.15) ^ heel
    minimum_peg = CrossSection.circle(diameter / 2 - 0.07, 72).translate(station)
    maximum_peg = CrossSection.circle(diameter / 2 + 0.05, 72).translate(station)
    require((minimum_peg - peg).area() < AREA_TOLERANCE and (peg - maximum_peg).area() < AREA_TOLERANCE,
            f"Peg at {station} falls outside the nominal {diameter:g} mm diameter")
    near_tip = leaf.slice(heel_height + insertion - 0.1) ^ heel
    require((near_tip ^ minimum_peg).area() > 1, f"Peg at {station} terminates before its nominal tip")
    require((leaf.slice(heel_height + insertion + 0.05) ^ heel).is_empty(),
            f"Peg at {station} exceeds the nominal insertion depth")

    upper_z = leaf.bounding_box()[5]
    heel_gauge = (heel - cavity).extrude(upper_z + 1).translate((0, 0, heel_height + 0.005))
    require((leaf ^ heel_gauge).volume() < VOLUME_TOLERANCE,
            f"Upright heel cannot seat or lift away at {station}")


def connects(space, probe):
    return (probe - space).area() < AREA_TOLERANCE


def check_upright_drain(leaf, station, heel_height):
    lower_x, lower_y, _, upper_x, upper_y, _ = leaf.bounding_box()
    window = (CrossSection.square((upper_x - lower_x + 6, upper_y - lower_y + 6))
              .translate((lower_x - 3, lower_y - 3)))
    x, y = station
    cavity = CrossSection.circle(3.1, 72).translate(station)
    heel = CrossSection.circle(7.2, 72).translate(station) - cavity
    seated_heel = heel.extrude(1).translate((0, 0, heel_height))
    underfloor = 0.85
    under_heel = heel_height - 0.15
    heel_paths = (window - leaf.slice(under_heel).offset(0.07)).decompose()
    counter_paths = (window - leaf.slice(underfloor).offset(0.25)).decompose()
    witness = CrossSection.circle(0.08, 24)
    exterior = witness.translate((lower_x - 2, lower_y - 2))
    socket_drop = witness.extrude(0.5)
    floor_drop = CrossSection.circle(0.35, 32).extrude(heel_height + 0.15 - underfloor)
    loaded = leaf + seated_heel
    for direction in (-1, 1):
        inlet = (x, y + direction * 2.95)
        outlet = (x, y + direction * 8.2)
        require((socket_drop.translate((*inlet, under_heel)) ^ loaded).volume() < 0.0001,
                f"Upright heel cavity at {station} cannot drain toward {direction:+d}Y")
        require(any(connects(channel, witness.translate(inlet)) and connects(channel, witness.translate(outlet))
                    for channel in heel_paths),
                f"Upright heel at {station} blocks the channel toward {direction:+d}Y")
        require((floor_drop.translate((*outlet, underfloor)) ^ loaded).volume() < VOLUME_TOLERANCE,
                f"Upright heel outlet at {outlet} does not clear the floor")
        require(any(connects(channel, exterior) and connects(channel, witness.translate(outlet))
                    for channel in counter_paths),
                f"Upright heel outlet at {outlet} cannot reach the exterior on a counter")


def check_crown_vents(closed):
    # Test a real port from beneath and above each packed crown. Both openings must
    # clear a 0.9 mm bore so a hairline seam cannot pass the ventilation check.
    port_heights = ((-1, HEEL_HEIGHT + 0.15, 1.5),
                    (2 * PIVOT[2] - HEEL_HEIGHT - 0.15, 2 * PIVOT[2] + 1, 2 * PIVOT[2] - 1.5))
    rim_witness = CrossSection.circle(3, 32)
    for direction, y in ((-1, -30.15), (1, -25.25)):
        for start, end, floor_height in port_heights:
            bore = Manifold.cylinder(end - start, 0.45, circular_segments=32)
            floor = closed.slice(floor_height)
            positions = ((direction * x, y) for x in (26, 32))
            require(any((bore.translate((*point, start)) ^ closed).volume() < VOLUME_TOLERANCE
                        and (floor ^ rim_witness.translate(point)).area() > 4 for point in positions),
                    f"Missing packed crown vent at X sign {direction:+d}, Z={start:g}")
    print("Both packed crowns have through vents below and above their bristle region")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mesh", nargs="?", type=Path, default=EXPORTS / "Storage-stand.stl")
    args = parser.parse_args()
    base, lid = read_leaves(args.mesh)
    check_flat_print(base, lid, STATIONS)
    hinge_shift = (0, 0, FOLDING_PIVOT_Z - PIVOT[2])
    check_hinge(base.translate(hinge_shift), lid.translate(hinge_shift))
    for leaf, station in zip((base, lid), STATIONS):
        check_upright_mount(leaf, station, HEEL_HEIGHT, PEG_DIAMETER, PEG_INSERTION)
        check_upright_drain(leaf, station, HEEL_HEIGHT)
    print("Both upright heel gauges seat on the floor and drain to the counter through two paths")

    gauge = travel_gauge()
    heads = [placement.place(gauge) for placement in PACKING_POSITIONS]
    closed = base + swing(lid, PIVOT, 180)
    latch_region = Manifold.cube((9, 5, 10)).translate((-4.5, -54.4, PIVOT[2] - 5))
    latch_projection = Manifold.cube((9, 5, 26)).translate((-4.5, -54.4, 0))
    hinge_region = Manifold.cube((27, 8.5, 26)).translate((-13.5, -4.25, 0))
    check_rectangular_shell(closed, SHELL_FOOTPRINT, (5, 10, 15.6, 20.6), hinge_region + latch_projection)
    check_freestanding_pegs(closed, SHELL_FOOTPRINT, STATIONS)
    check_enclosure(closed, heads, PACKING_POSITIONS, PACKED_ENVELOPE, SHELL_FOOTPRINT)
    check_insertion(base, lid, gauge, PACKING_POSITIONS)
    check_shaft_support(base, gauge, PACKING_POSITIONS)
    check_motion(base, lid, PIVOT, heads, latch_region)
    check_latch_retention(base, lid, PIVOT, latch_region)
    check_transport(closed, gauge, PACKING_POSITIONS)
    check_combined_transport(closed, gauge, PACKING_POSITIONS)
    check_heel_pivot_transport(closed, gauge, PACKING_POSITIONS)
    check_crown_vents(closed)


if __name__ == "__main__":
    main()
