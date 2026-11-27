"""Check the delivered binary STLs for the default Headstand design."""

from pathlib import Path
import struct

import numpy as np
from manifold3d import CrossSection, Error, Manifold, Mesh


EXPORTS = Path(__file__).resolve().parents[1] / "exports"
PIVOT_Y = 24.6
PIVOT_Z = 16.0
SOCKETS = ((-15, -6), (8, -6))
VOLUME_TOLERANCE = 0.002  # cubic millimeters


def require(condition, problem):
    if not condition:
        raise ValueError(problem)


def read_solid(filename):
    data = (EXPORTS / filename).read_bytes()
    require(len(data) >= 84, f"{filename}: incomplete STL header")
    count = struct.unpack_from("<I", data, 80)[0]
    require(len(data) == 84 + 50 * count, f"{filename}: invalid binary STL size")
    facets = np.dtype([("normal", "<f4", 3), ("points", "<f4", (3, 3)), ("attribute", "<u2")])
    points = np.frombuffer(data, dtype=facets, offset=84)["points"].reshape(-1, 3)
    require(np.isfinite(points).all(), f"{filename}: nonfinite vertex")
    vertices, inverse = np.unique(points, axis=0, return_inverse=True)
    faces = inverse.reshape(-1, 3).astype(np.uint32)
    corners = vertices[faces].astype(np.float64)
    normals = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    require(np.all(np.linalg.norm(normals, axis=1) > 0), f"{filename}: degenerate facet")
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    _, uses = np.unique(np.sort(edges, axis=1), axis=0, return_counts=True)
    require(np.all(uses == 2), f"{filename}: open or nonmanifold edge")
    solid = Manifold(Mesh(np.ascontiguousarray(vertices), faces))
    require(solid.status() == Error.NoError, f"{filename}: {solid.status()}")
    require(solid.volume() > 0 and len(solid.decompose()) == 1, f"{filename}: expected one solid")
    require(abs(solid.bounding_box()[2]) < 0.005, f"{filename}: sole must sit at Z=0")
    print(f"{filename}: {count} facets, one manifold solid, {solid.volume() / 1000:.2f} cm³")
    return solid


def swing_lid(lid, degrees):
    # Zero is flat on the counter. An actual printed lid can only translate and rotate.
    return (lid.translate((0, PIVOT_Y, -PIVOT_Z))
            .rotate((degrees, 0, 0)).translate((0, PIVOT_Y, PIVOT_Z)))


def packed_heads():
    # Synthetic clearance gauges, in mm. Two profiles represent heel, tapered stem
    # and a conservative round 17 × 22 mm crown. These are not measured brush scans.
    def stem(x, length, diameter1, diameter2):
        return (Manifold.cylinder(length, diameter1 / 2, diameter2 / 2, circular_segments=64)
                .rotate((0, 90, 0)).translate((x, 0, 10.35)))

    shaft = stem(-37, 9, 14.4, 14.4) + stem(-28, 28, 14.4, 10.4) + stem(0, 29, 10.4, 8.5)
    crown = Manifold.cylinder(22, 8.5, circular_segments=64).translate((28.5, 0, 4.7))
    head = shaft + crown
    return head.translate((0, -10.2, 0)) + head.translate((0, 10.2, 0))


def check_motion(tray, lid):
    pin = (Manifold.cylinder(80, 1.75 / 2, circular_segments=48)
           .rotate((0, 90, 0)).translate((-40, PIVOT_Y, PIVOT_Z)))
    for part in (tray, swing_lid(lid, 0)):
        require((pin ^ part).volume() < VOLUME_TOLERANCE, "1.75 mm hinge pin obstructed")
        require((pin.translate((0, 1.5, 0)) ^ part).volume() > 0.5,
                "No bearing alongside the hinge pin")
        require(part.slice(0.05).area() > 2300, "Too little flat bearing area at the counter")
    # The flexible front catch may deflect on the ramp during the last degrees of closure.
    latch_region = Manifold.cube((26, 8, 13)).translate((-13, -29, 12))
    angles = sorted(set(range(0, 181, 2)) | {179, 179.5, 179.75})
    heads = packed_heads()
    require((heads ^ tray).volume() < VOLUME_TOLERANCE, "Travel saddles foul a packed head gauge")
    latch_engaged = False
    for angle in angles:
        positioned = swing_lid(lid, angle)
        require((positioned ^ heads).volume() < VOLUME_TOLERANCE, f"Lid fouls a head gauge at {angle}°")
        overlap = tray ^ positioned
        if angle in (0, 180):
            require(overlap.volume() < VOLUME_TOLERANCE, f"Resting collision at {angle}°")
        elif overlap.volume() > VOLUME_TOLERANCE:
            require(angle > 165 and (overlap - latch_region).volume() < VOLUME_TOLERANCE,
                    f"Rigid case geometry interferes at {angle}°")
            latch_engaged = True
    require(latch_engaged, "No latch engagement on sampled closing path")
    closed = tray + swing_lid(lid, 180)
    bounds = np.array(closed.bounding_box())
    dimensions = bounds[3:] - bounds[:3]
    require((dimensions <= [82, 55, 32.5]).all(), f"Packed envelope grew to {dimensions}")
    print(f"Packed envelope: {' × '.join(f'{d:.1f}' for d in dimensions)} mm")
    print(f"Pin path clear; checked shells and two packed gauges at {len(angles)} opening angles")


def check_sockets(lid):
    for x, y in SOCKETS:
        heel = Manifold.cylinder(14, 7.4, circular_segments=64).translate((x, y, 3.21))
        require((heel ^ lid).volume() < VOLUME_TOLERANCE, f"14.8 mm heel gauge obstructed at X={x}")
        # A gauge in empty space also clears. Confirm the collar surrounds it at two levels.
        for z in (6.5, 10.5):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                hits = lid.ray_cast((x, y, z), (x + dx * 10.5, y + dy * 10.5, z))
                require(bool(hits), f"Incomplete upright support at X={x}, Z={z}")
    print("Both upright sockets admit a 14.8 mm gauge with surrounding lateral support")


def check_drainage(tray, lid):
    for y in (-10.2, 10.2):
        require(not tray.ray_cast((28, y, 2.7), (50, y, 2.7)), f"Blocked storage lane drain at Y={y}")
    # Below a seated heel, one connected air space must reach both the socket and open air.
    plane = CrossSection.square((130, 100), center=True)
    outside = CrossSection.circle(0.5).translate((0, 40))
    inlets = [CrossSection.circle(0.6).translate((x, y)) for x, y in SOCKETS]
    for z in (2.65, 2.8, 2.95, 3.1):
        spaces = (plane - lid.slice(z)).decompose()
        for space in spaces:
            if (space ^ outside).area() > 0.1 and all((space ^ inlet).area() > 0.1 for inlet in inlets):
                print(f"Both sockets drain to the exterior below the heels at Z={z:.2f} mm; travel ports clear")
                return
    raise ValueError("No common horizontal drainage path found below the two seated heels")


if __name__ == "__main__":
    tray = read_solid("Travel-tray.stl")
    lid = read_solid("Stand-lid.stl")
    sample = read_solid("Socket-sample.stl")
    sample_center = SOCKETS[1]
    sample_region = Manifold.cylinder(14, 9.7, circular_segments=72).translate((*sample_center, 0))
    require(((lid - sample) ^ sample_region).volume() < VOLUME_TOLERANCE and
            ((sample - lid) ^ sample_region).volume() < VOLUME_TOLERANCE,
            "Fit sample differs from the corresponding lid socket")
    check_motion(tray, lid)
    check_sockets(lid)
    check_drainage(tray, lid)
