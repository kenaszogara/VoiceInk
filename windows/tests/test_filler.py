import pytest

from voiceink_win.filler import DEFAULT_WORDS_FILE, load_words, remove_fillers

WORDS = load_words(DEFAULT_WORDS_FILE)


@pytest.mark.parametrize(
    "dictated, cleaned",
    [
        ("So, um, I think we should, like, ship it, you know?", "So I think we should ship it?"),
        ("Um, uh, the build is green.", "The build is green."),
        ("Uh. Okay, so, you know, it works.", "Okay, so it works."),
        ("Like, this is, uh, basically done.", "This is basically done."),
        ("I mean, it's fine. I like it.", "It's fine. I like it."),
        ("Do you know him? I mean it.", "Do you know him? I mean it."),
        ("It's kind of big and sort of blue.", "It's kind of big and sort of blue."),
        ("The umbrella is humming.", "The umbrella is humming."),
        ("Um", ""),
    ],
)
def test_remove_fillers(dictated, cleaned):
    assert remove_fillers(dictated, WORDS) == cleaned


def test_user_list_is_respected(tmp_path):
    words_file = tmp_path / "filler_words.txt"
    words_file.write_text("# mine\nokay  # trailing comment\n~right\n", encoding="utf-8")
    words = load_words(words_file)

    assert words == ["okay", "~right"]
    assert remove_fillers("Okay, turn right, right, then um stop.", words) == "Turn right then um stop."
