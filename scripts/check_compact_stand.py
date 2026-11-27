"""Check the compact stand's delivered mesh against the default fit envelope."""

import numpy as np
from manifold3d import CrossSection, Manifold

from check_meshes import VOLUME_TOLERANCE, read_solid, require


STATIONS = (-12.0, 12.0)
HEEL_SEAT = 5.2


def support_margin(contact, point):
    """Distance inside the convex support polygon, measured normal to its closest edge."""
    outline, = contact.hull().to_polygons()
    edges = np.roll(outline, -1, axis=0) - outline
    offsets = np.asarray(point) - outline
    distances = (edges[:, 0] * offsets[:, 1] - edges[:, 1] * offsets[:, 0]) / np.linalg.norm(edges, axis=1)
    return float(np.min(distances))


def check_base(stand):
    bounds = np.asarray(stand.bounding_box())
    size = bounds[3:] - bounds[:3]
    require(np.allclose(size, (50, 32, 12.2), atol=0.02), f"Unexpected travel envelope: {size}")
    sole = stand.slice(0)
    require(sole.area() > 1300, "Underside lost its broad flat contact patch")
    # Level counter, vertical loads at either head axis or their midpoint.
    margins = [support_margin(sole, (x, 0)) for x in (*STATIONS, 0)]
    require(min(margins) >= 12, "A centered single-head load is too close to a tipping edge")
    print(f"Flat sole {sole.area():.0f} mm²; closest tipping edge {min(margins):.1f} mm from a peg axis")


def check_pegs(stand):
    above_seat = stand.trim_by_plane((0, 0, 1), HEEL_SEAT + 0.01)
    require(len(above_seat.decompose()) == 2, "Expected exactly two exposed locating pegs")
    # Two blind cylindrical gauge cavities, Ø6.2 mm and 7.5 mm deep. No real head scan is implied.
    cavity = Manifold.cylinder(7.5, 3.1, circular_segments=72)
    cavities = [cavity.translate((x, 0, HEEL_SEAT)) for x in STATIONS]
    require((above_seat - (cavities[0] + cavities[1])).volume() < VOLUME_TOLERANCE,
            "A peg or an exterior collar interferes with the seated gauges")

    for x in STATIONS:
        toe = CrossSection.circle(7.2, 72).translate((x, 0))
        inner = CrossSection.circle(5.1, 72).translate((x, 0))
        # A loose pin also fits the hollow gauge. Check locating diameter on both sides of nominal.
        peg_seat = stand.slice(HEEL_SEAT + 0.01) ^ toe
        minimum_peg = CrossSection.circle(2.75, 72).translate((x, 0))
        maximum_peg = CrossSection.circle(2.85, 72).translate((x, 0))
        require((minimum_peg - peg_seat).area() < 0.001 and (peg_seat - maximum_peg).area() < 0.001,
                f"Peg at X={x} falls outside the 5.6 ± 0.1 mm locating diameter")
        contact = stand.slice(HEEL_SEAT - 0.01) ^ (toe - inner)
        require(len(contact.decompose()) == 3, f"Heel rim at X={x} needs three independent supports")
        require(support_margin(contact, (x, 0)) > 2, f"Heel rim at X={x} cannot carry a centered head")
        require((stand.slice(HEEL_SEAT + 6.5) ^ toe).area() > 1, f"Short or missing peg at X={x}")


def check_drainage(stand):
    # A horizontal path from under the heel to beyond the base proves the opening
    # stays clear on a counter. A sealed ring at the same height must block it.
    window = CrossSection.square((80, 60), center=True)
    obstacles = stand.slice(4.8)
    outside = CrossSection.circle(0.3, 24).translate((0, -24))
    for x in STATIONS:
        inlet = CrossSection.circle(0.3, 24).translate((x, -4.5))
        seal = (CrossSection.circle(8, 72) - CrossSection.circle(7, 72)).translate((x, 0))
        for barrier, should_drain in ((obstacles, True), (obstacles + seal, False)):
            passages = (window - barrier.offset(0.35)).decompose()
            drains = any((space ^ inlet).area() > 0.25 and (space ^ outside).area() > 0.25 for space in passages)
            require(drains == should_drain, f"Unexpected under-heel drainage at X={x}, seal={not should_drain}")


if __name__ == "__main__":
    stand = read_solid("Compact-stand.stl")
    check_base(stand)
    check_pegs(stand)
    check_drainage(stand)
    print("Both peg gauges seat on three pads; open under-heel passages clear both sealed-ring controls")
