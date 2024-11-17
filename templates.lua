local templates = {}
local vb = renoise.ViewBuilder()

--Add Single Instrument Templates
--Euclidean, Buzz, Accent, Paradiddle, Double Paradiddle, Crossover, Dotted

--Shuffle Templates
templates.basic_snare_hat_shuffle = {
    S = "....|S...|....|S...", 
    G = ".G.G|....|.G.G|....",
    H = "H.H.|.H.H|H.H.|.H.H"
}

templates.syncopated_ghost_shuffle = {
    S = "....|S...|....|....", 
    G = "G..G|.G..|..G.|G...",
    H = ".H..|..H.|.H.H|..H."
}

templates.hat_driven_shuffle = {
    S = "....|S...|....|....", 
    G = ".G..|..G.|.G..|..G.",
    H = "H..H|H..H|H..H|H..H"
}

templates.complex_shuffle = {
    S = "....|S...|....|S...", 
    G = "G.G.|.G..|G..G|.G..",
    H = ".H.H|...H|.H..|...H"
}

templates.triplet_feel_shuffle = {
    S = "....|S...|....|S...", 
    G = "..G.|.G..|..G.|...G",
    H = ".H.H|...H|.H.H|.H.."
}

templates.kick_hat_shuffle = {
    K = "K...|....|K...|....", 
    H = "..H.|.H.H|..H.|.H.H"
}

templates.syncopated_kick_shuffle = {
    K = "K...|..K.|K...|.K..", 
    H = "..H.|H...|..H.|H.H."
}

templates.ghost_kick_shuffle = {
    K = "K...|....|K...|....", 
    L = "..L.|..L.|..L.|..L.",
    H = ".H.H|H..H|.H.H|H..H"
}

templates.rolling_hat_shuffle = {
    K = "K...|..K.|K...|....", 
    H = ".HHH|HH.H|.HHH|HHHH"
}

templates.interplay_shuffle = {
    K = "K...|.K..|..K.|K...", 
    L = "....|...L|....|...L",
    H = ".H.H|H...|.H.H|H..."
}

templates.two_step_shuffle = {
    K = "K...|...K|..K.|....", 
    S = "....|S...|....|S...",
    G = ".G.G|....|.G.G|...."
}

templates.syncopated_kick_snare_shuffle = {
    K = "K...|.K..|K...|..K.", 
    S = "....|S...|....|S...",
    G = "...G|...G|.G..|...G"
}

templates.rolling_snare_shuffle = {
    K = "K...|....|K...|....", 
    S = "....|S...|....|S...",
    G = ".GG.|.GG.|.GG.|.GG."
}

templates.complex_kick_shuffle = {
    K = "K.K.|..K.|K..K|....", 
    S = "....|S...|....|S...",
    G = "...G|....|.G..|...."
}

templates.ghost_groove_shuffle = {
    K = "K...|....|K...|....", 
    S = "....|S...|....|S...",
    G = "..G.|.G.G|..G.|.G.G"
}


--Add Multi-Instrument Templates
--Polyrhythm, Jazz, Latin

return templates