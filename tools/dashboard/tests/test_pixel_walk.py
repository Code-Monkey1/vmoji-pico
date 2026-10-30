"""The pixel walk: order, ack parsing, scoring and the CSV it hands over.

The CSV is what a brightness investigation starts from, so its shape is pinned
here: every pixel present, in walk order, with blanks rather than guesses for
what was not scored or not reported.
"""

from __future__ import annotations

import csv
import io

import pytest

import pixel_walk


def test_order_is_top_left_to_bottom_right_row_by_row():
    order = pixel_walk.walk_order()
    assert len(order) == len(set(order)) == 64
    assert order[:2] == [(0, 0), (0, 1)]
    assert order[8] == (1, 0)
    assert order[-1] == (7, 7)


def test_ack_with_gpios_is_parsed():
    ack = pixel_walk.parse_pixel_ack("OK pixel r3 c5 row=GP21 col=GP9")
    assert ack == pixel_walk.PixelAck(3, 5, 21, 9)


def test_ack_without_gpios_comes_from_the_simulator():
    assert pixel_walk.parse_pixel_ack("OK pixel r2 c6") == pixel_walk.PixelAck(2, 6)


@pytest.mark.parametrize("text", ["OK glyph 4", "ERR pixel row 0-7 col 0-7", "OK pixel r3", ""])
def test_other_lines_are_not_pixel_acks(text):
    assert pixel_walk.parse_pixel_ack(text) is None


def test_rating_scores_the_lit_pixel_then_advances():
    walk = pixel_walk.PixelWalk()
    assert walk.rate(4) is True
    assert walk.ratings == {(0, 0): 4}
    assert walk.current == (0, 1)


def test_rating_the_last_pixel_stays_put():
    walk = pixel_walk.PixelWalk()
    walk.index = len(walk.order) - 1
    assert walk.rate(0) is False
    assert walk.current == (7, 7)
    assert walk.ratings == {(7, 7): 0}


def test_out_of_range_score_is_refused():
    walk = pixel_walk.PixelWalk()
    with pytest.raises(ValueError):
        walk.rate(pixel_walk.MAX_SCORE + 1)
    assert walk.ratings == {}
    assert walk.index == 0


def test_navigation_stops_at_both_ends():
    walk = pixel_walk.PixelWalk()
    assert walk.prev() is False
    assert walk.next() is True
    walk.index = len(walk.order) - 1
    assert walk.next() is False


def test_restart_keeps_scores():
    walk = pixel_walk.PixelWalk()
    walk.rate(3)
    walk.restart()
    assert walk.current == (0, 0)
    assert walk.ratings == {(0, 0): 3}


def test_label_adds_gpios_and_score_once_known():
    walk = pixel_walk.PixelWalk()
    assert walk.label() == "r0 c0"
    walk.note_ack(pixel_walk.PixelAck(0, 0, 22, 18))
    walk.ratings[(0, 0)] = 2
    assert walk.label() == "r0 c0 · row GP22 · col GP18 · scored 2"


def test_csv_lists_every_pixel_with_blanks_for_unknowns():
    walk = pixel_walk.PixelWalk()
    walk.note_ack(pixel_walk.PixelAck(0, 0, 22, 18))
    walk.rate(5)

    rows = list(csv.DictReader(io.StringIO(walk.to_csv())))

    assert len(rows) == 64
    assert rows[0] == {"row": "0", "col": "0", "row_gpio": "22", "col_gpio": "18", "score": "5"}
    assert rows[1] == {"row": "0", "col": "1", "row_gpio": "", "col_gpio": "", "score": ""}
