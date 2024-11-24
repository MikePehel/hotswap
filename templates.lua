local templates = {}
local vb = renoise.ViewBuilder()

--TODO Add Paradiddle and Crossover Multi-Sample Rolls
--TODO Add more genres to beat templates

--Paradiddles & Crossovers
templates._p_paradiddle = {
    R = "R.RR|.R..|R.RR|.R..",
    L = ".L..|L.LL|.L..|L.LL",
    steps = 16
}

templates._p_dbl_paradiddle = {
    R = "R.R.|RR.R|.R..",
    L = ".L.L|..L.|L.LL",
    steps = 12
}

templates._p_trpl_paradiddle = {
    R = "R.R.|R.RR|.R.R|.R..",
    L = ".L.L|.L..|L.L.|L.LL",
    steps  = 16  
}


templates._c_crossover = {
    R = "R..R|R.R.|.RR.|.R.R",
    L = ".LL.|.L.L|L..L|L.L.",
    V = "4848|4868|6868|4868",
    steps  = 16  

}

templates._c_dbl_crossover = {
    R = "R..R|R..R|.RR.|.RR.",
    L = ".LL.|.LL.|L..L|L..L",
    V = "4848|4646|4848|4646",
    steps  = 16  

}

--Complex Rolls
templates._r_syncopated_roll = {
    R = "R...|R...",
    L = "...L|...L",
    steps  = 8   
}


templates._r_bouncing_decay_roll__ = {
    R = "R.R.|R...|R...|..R.|....|..R.|....|....",
    L = ".L.L|..L.|...L|....|..L.|....|...L|....",
    steps  = 16  
}

templates._r_downbeat_accent_roll = {
    R = "R.R.|....",
    L = ".L.L|..L.",
    V = "1234|..8.",
    steps  = 8  
}

templates._m_multi_roll = {
    R = "R...|R...",
    L = "..L.|..L.",
    G = ".G..|.G..",
    H = "...H|...H",
    steps  = 8
}

templates._m_weak_hand = {
    R = ".R..|.R..",
    L = "...L|...L",
    G = "G...|G...",
    H = "..H.|..H.",
    steps  = 8
}

templates._m_weak_strong = {
    R = "....|R.R.",
    L = "....|.L.L",
    G = "G.G.|....",
    H = ".H.H|....",
    steps = 8    
}

templates._m_strong_weak = {
    R = "R.R.|....",
    L = ".L.L|....",
    G = "....|G.G.",
    H = "....|.H.H",
    steps = 8    
}


--Shuffle Templates
templates.basic_snare_hat_shuffle = {
    S = "....|S...|....|S...", 
    G = ".G.G|....|.G.G|....",
    H = "H.H.|.H.H|H.H.|.H.H",
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


--Multi-Instrument Templates

-- Latin
----Samba
templates._l_basic_samba = {
    K = "K...K...K...K...|K...K...K...K...|K...K...K...K...|K...K...K...K...",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO",
    G = "..G...G...G...G.|..G...G...G...G.|..G...G...G...G.|..G...G...G...G."
}

templates._l_traditional_samba = {
    K = "K...K.K.K...K.K.|K...K.K.K...K.K.|K...K.K.K...K.K.|K...K.K.K...K.K.",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO",
    G = "..G...G...G...G.|..G...G...G...G.|..G...G...G...G.|..G...G...G...G."
}

templates._l_syncopated_samba = {
    K = "K.K.....K.K.....|K.K.....K.K.....|K.K.....K.K.....|K.K.....K.K.....",
    S = "....S.......S...|....S.........S.|....S.......S...|....S.........S.",
    H = "H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO",
    G = "..G...G...G...G.|......G.....G...|..G...G...G...G.|......G.....G..."    
}

templates._l_modern_samba = {
    K = "K...K...K.K.K...|K...K...K.K.K...|K...K...K.K.K...|K...K...K.K.K...",
    S = "....S.S.......S.|....S.S.......S.|....S.S.......S.|....S.S.......S.",
    H = "H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "..G.....G...G...|..G.....G...G...|..G.....G...G...|..G.....G...G..."
    
}

---- Afro Cuban
templates._u_san_clave = {
    K = "K.....K.K....K..|K.....K.K....K..|K.....K.K....K..|K.....K.K....K..",
    S = "....S.....S.....|....S.....S.....|....S.....S.....|....S.....S.....",
    H = "H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO",
    G = "..G...G.......G.|..G.....G...G...|..G...G.......G.|..G.....G...G..."    
}

templates._u_rumba_clave = {
    K = "K...K...K.K.....|K...K...K.K.....|K...K...K.K.....|K...K...K.K.....",
    S = "....S.....S.....|....S.....S.S...|....S.....S.S...|....S.....S.S...",
    H = "H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.H.|H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "G.....G.....G...|G.....G.........|G.....G.........|G.....G........."    
}

templates._u_mozambique = {
    K = "K..K..K...K.....|K..K..K...K.....|K..K..K...K.....|K..K..K...K.....",
    S = "......S...S...S.|......S...S...S.|......S...S...S.|......S...S...S.",
    H = "H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO",
    G = "G...G...G...G...|G...G...G...G...|G...G...G...G...|G...G...G...G..."  
}

templates._u_guaguanco = {
    K = "K.K...K...K.K...|K.K...K...K.K...|K.K...K...K.K...|K.K...K...K.K...",
    S = "....S.S...S.....|....S.S...S.....|....S.S...S.....|....S.S...S.....",
    H = "H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "..G.....G.....G.|..G.....G.....G.|..G.....G.....G.|..G.....G.....G."  
}

--Afrobeat
templates._a_fela_style = {
    K = "K..K..K...K.K...|K..K..K...K.K...|K..K..K...K.K...|K..K..K...K.K...",
    S = "....S.....S.S...|....S.....S.S...|....S.....S.S...|....S.....S.S...",
    H = "H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO",
    G = "G.G.....G.......|G.G.....G.......|G.G.....G.......|G.G.....G......."    
}

templates._a_allen_style = {
    K = "K...K.K...K.....|K...K.K...K.....|K...K.K...K.....|K...K.K...K.....",
    S = "....S...S...S.S.|....S...S...S.S.|....S...S...S.S.|....S...S...S.S.",
    H = "H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "G.G.............|G.G.............|G.G.............|G.G............."    
}

templates._a_lagos_shuffle = {
    K = "K.K...K.K...K...|K.K...K.K...K...|K.K...K.K...K...|K.K...K.K...K...",
    S = "....S.S.....S.S.|....S.S.....S.S.|....S.S.....S.S.|....S.S.....S.S.",
    H = "H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "G.........G.....|G.........G.....|G.........G.....|G.........G....."    
}

templates._a_lagos_twist = {
    K = "K..K.K..K.K..K..|K..K.K..K.K..K..|K..K.K..K.K..K..|K..K.K..K.K..K..",
    S = "....S...S.S.....|....S...S.S.....|....S...S.S.....|....S...S.S.....",
    H = "H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.HO",
    G = "G............G..|G............G..|G............G..|G............G.."    
}

--Jazz
templates._j_basic_swing = {
    K = "K.......K.......|K.......K.......|K.......K.......|K.......K.......",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H..H.H..H..H.H..|H..H.H..H..H.H..|H..H.H..H..H.H..|H..H.H..H..H.H..",
    G = "...G.....G...G..|...G.....G...G..|...G.....G...G..|...G.....G...G.."    
}

templates._j_bebop = {
    K = "K.......K...K...|K.......K...K...|K.......K...K...|K.......K...K...",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H..H.H..H..H.H.O|H..H.H..H..H.H..|H..H.H..H..H.H.O|H..H.H..H..H.H..",
    G = "G.......G.......|G.......G.......|G.......G.......|G.......G......."    
    
}

templates._j_jazz_waltz = {
    K = "K.....K.........|K.....K.........|K.....K.........|K.....K.........",
    S = "....S.....S.....|....S.....S.....|....S.....S.....|....S.....S.....",
    H = "H..H.H..H..H.H..|H..H.H..H..H.H.O|H..H.H..H..H.H..|H..H.H..H..H.H.O",
    G = ".G.......G......|.G.......G......|.G.......G......|.G.......G......"    
    
}
templates._j_hard_bop = {
    K = "K.......K..K....|K.......K..K....|K.......K..K....|K.......K..K....",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H..H.H..H..H.H.O|H..H.H..H..H.H..|H..H.H..H..H.H.O|H..H.H..H..H.H..",
    G = "...G..G.........|...G..G.........|...G..G.........|...G..G........."    
    
}
templates._j_contemporary_jazz = {
    K = "K.....K.K.......|K.....K.K.......|K.....K.K.......|K.....K.K.......",
    S = "....S.......S...|....S.......S...|....S.......S...|....S.......S...",
    H = "H..H.H..H..H.H.O|H..H.H..H..H.H..|H..H.H..H..H.H.O|H..H.H..H..H.H..",
    G = "...G..G.........|...G..G.........|...G..G.........|...G..G........."    
    
}

--Funk
templates._f_classic_funk = {
    K = "K.....K...K.....|K.....K...K.....|K.....K...K.....|K.....K...K.....",
    S = "....S.....S...S.|....S.....S...S.|....S.....S...S.|....S.....S...S.",
    H = "H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.HO",
    G = "G...........G...|G...........G...|G...........G...|G...........G..."    
    
}

templates._f_syncopated_funk = {
    K = "K..K..K...K.K...|K..K..K...K.K...|K..K..K...K.K...|K..K..K...K.K...",
    S = "...S...S....S...|...S...S....S...|...S...S....S...|...S...S....S...",
    H = "H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.H.|H.H.H.HOH.H.H.H.",
    G = ".G.......G......|.G.......G......|.G.......G......|.G.......G......"    

}

templates._f_new_orleans_funk = {
    K = "K..K...K..K...K.|K..K...K..K...K.|K..K...K..K...K.|K..K...K..K...K.",
    S = "....S.....S.....|....S.....S.....|....S.....S.....|....S.....S.....",
    H = "H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO|H.H.H.H.H.H.H.H.|H.H.H.H.H.H.H.HO",
    G = ".....G.......G..|.....G.......G..|.....G.......G..|.....G.......G.."    

}

templates._f_modern_pocket = {
    K = "K.K...K...K.K...|K.K...K...K.K...|K.K...K...K.K...|K.K...K...K.K...",
    S = "....S.....S.....|....S.....S.....|....S.....S.....|....S.....S.....",
    H = "H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO|H.H.H.HOH.H.H.HO",
    G = ".......G......G.|.......G......G.|.......G......G.|.......G......G."    

}

--Linear
templates._i_basic_linear = {
    P = "K..H.S.H.K..H.S.|K..H.S.H.K..H.S.|K..H.S.H.K..H.S.|K..H.S.H.K..H.S."

}

templates._i_linear_funk = {
    P = "K.H.S.H.K.G.H.S.|K.H.S.H.K.G.H.S.|K.H.S.H.K.G.H.S.|K.H.S.H.K.G.H.S."

}

templates._i_linear_latin = {
    P = "K.H.S.G.K.H.S.H.|K.H.S.G.K.H.S.H.|K.H.S.G.K.H.S.H.|K.H.S.G.K.H.S.H."

}

templates._i_complex_linear = {
    P = "K.H.S.G.H.S.K.H.|S.G.H.K.S.H.G.H.|K.H.S.G.H.S.K.H.|S.G.H.K.S.H.G.H."

}

templates._i_advanced_linear = {
    K = "K.O.S.G.H.G.K.O.|S.G.H.K.S.O.G.H.|K.H.S.G.O.S.k.H.|S.G.O.K.G.H.G.O.",
    V = "8.8.8.4.8.4.4.8.|4.8.8.8.8.8.8.8.|8.8.4.8.8.8.4.8.|8.4.8.8.4.8.8.8."
}


return templates