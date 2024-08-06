package main

import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"
import rand "core:math/rand"

import ui   "vendor:microui"
import rl   "vendor:raylib"

vec2 :: [2]f32;
vec3 :: [3]f32;
vec4 :: [4]f32;

ivec2 :: [2]i32;
ivec3 :: [3]i32;
ivec4 :: [4]i32;

UPDATE_RATE :: 0.0697

MAX_PLAYERS :: 10;
MAX_ROCKS   :: 200;
MAX_TREES   :: 200;

TILE_SIZE   :: 8;

entity_archetype :: enum
{
    NIL    = 0,
    PLAYER = 1,
    ROCK   = 2,
    TREE00 = 3,
};

texture_index :: enum
{
    NIL  = 0,
    GAME = 1,
};

sprites :: enum
{
    NIL             = 0,
    PLAYER_IDLE     = 1,
    SPRITE_ROCK     = 2,
    SPRITE_TREE00   = 3,
//    PLAYER_RUNNING,
//    PLAYER_DEAD,
};

entity_flags :: enum u32
{
    IS_VALID       = 1,
    IS_ALIVE       = 2,
    IS_PLAYER      = 3,
    IS_ENVIRONMENT = 4,
};

entity_flag_bits :: distinct bit_set[entity_flags; u32];

sprite_data :: struct 
{
    Offset         : vec2,
    SpriteSize     : vec2,
    FrameCount     : i32,
};

entity :: struct
{
    Archetype        : entity_archetype,
    Health           : i32,
    Flags            : entity_flag_bits,
    Position         : rl.Vector2,
    Sprite           : sprites,
    TextureSource    : rl.Rectangle,
    OutputDest       : rl.Rectangle,
    Collider         : rl.Rectangle,
    Speed            : vec2,
};

world :: struct 
{
    Rocks         : [200]entity,
    Trees         : [200]entity,
    Players       : [10]entity,
    PlayerCounter : u32,
    RockCounter   : u32,
    TreeCounter   : u32,
};

state :: struct 
{
    WindowSize   : ivec4,
    SpriteSheets : [texture_index]rl.Texture2D,
    Sprites      : [sprites]sprite_data,

    World : world,
};

Equals :: proc (A : f32, B : f32, Tolerance : f32) -> bool
{
    return(math.abs(A - B) <= Tolerance);
}

Approach :: proc(Value : ^f32, Target : f32, Rate : f32, Delta_t : f32)
{
    Value^ += f32((Target - Value^) * (1.0 - math.pow(2.0, -Rate * Delta_t)));
    if(Equals(Value^, Target, 0.001))
    {
        Value^ = Target;
    }
}

v2Approach :: proc(Value : ^vec2, Target : vec2, Rate : f32, Delta_t : f32)
{
    Approach(&Value.x, Target.x, Rate, Delta_t);    
    Approach(&Value.y, Target.y, Rate, Delta_t);    
}

CreateEntity :: proc(Arch : entity_archetype, State : ^state) -> ^entity
{
    Result : ^entity = {};

    #partial switch(Arch)
    {
        case .PLAYER:
        {
            for EntityIndex := 0; EntityIndex < MAX_PLAYERS; EntityIndex += 1
            {
                Found : ^entity = &State.World.Players[EntityIndex];
                if(entity_flag_bits.IS_VALID not_in Found.Flags)
                {
                    Result = Found;
                    State.World.PlayerCounter += 1;
                    break;
                }
            }
        };
        case .ROCK:
        {
            for EntityIndex := 0; EntityIndex < MAX_ROCKS; EntityIndex += 1
            {
                Found : ^entity = &State.World.Rocks[EntityIndex];
                if(entity_flag_bits.IS_VALID not_in Found.Flags)
                {
                    Result = Found;
                    State.World.RockCounter += 1;
                    break;
                }
            }
        };
        case .TREE00:
        {
            for EntityIndex := 0; EntityIndex < MAX_TREES; EntityIndex += 1
            {
                Found : ^entity = &State.World.Trees[EntityIndex];
                if(entity_flag_bits.IS_VALID not_in Found.Flags)
                {
                    Result = Found;
                    State.World.TreeCounter += 1;
                    break;
                }
            }
        }
    }

    Result.Flags = {.IS_VALID};
    return(Result);
}

LoadData :: proc(State : ^state)
{
    State.SpriteSheets = 
    {
        .NIL = {},
        .GAME = rl.LoadTexture("../data/res/textures/MainAtlas.png"),
    };

    State.Sprites = 
    {
        .NIL = {},
        .PLAYER_IDLE    = {Offset = {0, 0},  SpriteSize = {8, 9},   FrameCount = 1},
        .SPRITE_ROCK    = {Offset = {16, 0}, SpriteSize = {10, 7},  FrameCount = 1},
        .SPRITE_TREE00  = {Offset = {32, 0}, SpriteSize = {11, 12}, FrameCount = 1},
    };
}

MovePlayer :: proc(Entity : ^entity, Delta_t : f32)
{
    InputAxis : vec2 = 0;

    if(rl.IsKeyDown(.W))
    {
        InputAxis.y -= 1.0; 
    }
    if(rl.IsKeyDown(.A))
    {
        InputAxis.x -= 1.0;        
    }
    if(rl.IsKeyDown(.S))
    {
        InputAxis.y += 1.0;        
    }
    if(rl.IsKeyDown(.D))
    {
        InputAxis.x += 1.0;        
    }
    InputAxis = linalg.normalize0(InputAxis);

    OldPlayerP : vec2 = Entity.Position;
    NewPlayerP : vec2 = 
    {
        Entity.Position.x + ((Entity.Position.x - OldPlayerP.x) + (Entity.Speed.x * InputAxis.x) * (Delta_t)),
        Entity.Position.y + ((Entity.Position.y - OldPlayerP.y) + (Entity.Speed.y * InputAxis.y) * (Delta_t))
    };
    Entity.Position = NewPlayerP;
}

SetupPlayer :: proc(Player : ^entity, State : ^state)
{
    Player.Archetype = .PLAYER;
    Player.Health = 2;
    Player.Sprite = sprites.PLAYER_IDLE;
    Player.Flags += {.IS_ALIVE, .IS_PLAYER};
    Player.Position = {0.0, 0.0};
    Player.TextureSource = 
    {
        State.Sprites[.PLAYER_IDLE].Offset.x, 
        State.Sprites[.PLAYER_IDLE].Offset.y, 
        State.Sprites[.PLAYER_IDLE].SpriteSize.x, 
        State.Sprites[.PLAYER_IDLE].SpriteSize.y
    };

    Player.Speed = {100.0, 100.0};
}

SetupRock :: proc(Rock : ^entity, State : ^state)
{
    Rock.Archetype = .ROCK;
    Rock.Health = 4;
    Rock.Sprite = sprites.SPRITE_ROCK;
    Rock.Flags += {.IS_ALIVE, .IS_ENVIRONMENT};
    Rock.Position = {0.0, 0.0};
    Rock.TextureSource = 
    {
        State.Sprites[.SPRITE_ROCK].Offset.x, 
        State.Sprites[.SPRITE_ROCK].Offset.y, 
        State.Sprites[.SPRITE_ROCK].SpriteSize.x, 
        State.Sprites[.SPRITE_ROCK].SpriteSize.y
    };
}

SetupTree :: proc(Tree : ^entity, State : ^state)
{
    Tree.Archetype = .TREE00;
    Tree.Health = 4;
    Tree.Sprite = sprites.SPRITE_TREE00;
    Tree.Flags += {.IS_ALIVE, .IS_ENVIRONMENT};
    Tree.Position = {0.0, 0.0};
    Tree.TextureSource = 
    {
        State.Sprites[.SPRITE_TREE00].Offset.x, 
        State.Sprites[.SPRITE_TREE00].Offset.y, 
        State.Sprites[.SPRITE_TREE00].SpriteSize.x, 
        State.Sprites[.SPRITE_TREE00].SpriteSize.y
    };
}

DeleteEntity :: proc(Entity : ^entity, State : ^state)
{
   runtime.memset(Entity, 0, size_of(entity));
}

UpdatePlayers :: proc(State : ^state, Camera : ^rl.Camera2D, Delta_t : f32)
{
    using State;

    for PlayerIndex : u32 = 0; PlayerIndex < State.World.PlayerCounter; PlayerIndex += 1
        {
            Entity : ^entity = &State.World.Players[PlayerIndex];

            MovePlayer(Entity, Delta_t);

            v2Approach(&Camera.target, Entity.Position, 10, Delta_t);
            Entity.OutputDest = {Entity.Position.x, Entity.Position.y, Sprites[.PLAYER_IDLE].SpriteSize.x, Sprites[.PLAYER_IDLE].SpriteSize.y};
            rl.DrawTexturePro(SpriteSheets[.GAME], 
                              Entity.TextureSource, 
                              Entity.OutputDest, 
                              {f32(Entity.TextureSource.width * 0.5), Entity.TextureSource.height}, 
                              0.0, 
                              rl.WHITE);

            Entity.Collider = 
            {
                Entity.Position.x - (Entity.OutputDest.width  * 0.5),
                Entity.Position.y - Entity.OutputDest.height, 
                Entity.OutputDest.width, 
                Entity.OutputDest.height
            };
//            rl.DrawRectangleRec(Entity.Collider, rl.RED);
        }
}

// TODO(Sleepster): Perhaps shove all the environment stuff into "update environment"
UpdateTrees :: proc(State : ^state, MousePos : vec2)
{
    using State;
    for TreeIndex : u32 = 0; TreeIndex < State.World.TreeCounter; TreeIndex += 1
    {
        Entity : ^entity = &State.World.Trees[TreeIndex];

        Entity.OutputDest = {Entity.Position.x, Entity.Position.y, Sprites[.SPRITE_TREE00].SpriteSize.x, Sprites[.SPRITE_TREE00].SpriteSize.y};
        rl.DrawTexturePro(SpriteSheets[.GAME], 
                          Entity.TextureSource, 
                          Entity.OutputDest, 
                          {f32(Entity.TextureSource.width * 0.5), Entity.TextureSource.height}, 
                          0.0, 
                          rl.WHITE);
        Entity.Collider = 
        {
            Entity.Position.x - (Entity.OutputDest.width  * 0.5),
            Entity.Position.y - Entity.OutputDest.height, 
            Entity.OutputDest.width, 
            Entity.OutputDest.height
        };
        
        if(rl.CheckCollisionPointRec(MousePos, Entity.Collider) && rl.IsMouseButtonPressed(.LEFT))
        {
            Entity.Health -= 1;
            if(Entity.Health <= 0)
            {
                DeleteEntity(Entity, State);
            }
        }
//            rl.DrawRectangleRec(Entity.Collider, rl.RED);
    }
}

UpdateRocks :: proc(State : ^state, MousePos : vec2)
{
    using State;
    for RockIndex : u32 = 0; RockIndex < State.World.RockCounter; RockIndex += 1
        {
            Entity : ^entity = &State.World.Rocks[RockIndex];

            Entity.OutputDest = {Entity.Position.x, Entity.Position.y, Sprites[.SPRITE_ROCK].SpriteSize.x, Sprites[.SPRITE_ROCK].SpriteSize.y};
            if(.IS_VALID in Entity.Flags)
            {
                rl.DrawTexturePro(SpriteSheets[.GAME], 
                                  Entity.TextureSource, 
                                  Entity.OutputDest, 
                                  {f32(Entity.TextureSource.width * 0.5), Entity.TextureSource.height}, 
                                  0.0, 
                                  rl.WHITE);
                Entity.Collider = 
                {
                    Entity.Position.x - (Entity.OutputDest.width  * 0.5),
                    Entity.Position.y - Entity.OutputDest.height, 
                    Entity.OutputDest.width, 
                    Entity.OutputDest.height
                };

                if(rl.CheckCollisionPointRec(MousePos, Entity.Collider) && rl.IsMouseButtonPressed(.LEFT))
                {
                    Entity.Health -= 1;
                    if(Entity.Health <= 0)
                    {
                        DeleteEntity(Entity, State);
                    }
                }
            }
//            rl.DrawRectangleRec(Entity.Collider, rl.RED);
        }
}

V2Floor :: proc(Input : vec2) -> vec2
{
    Result : vec2 = {};
    Result.x = math.floor_f32(Input.x);
    Result.y = math.floor_f32(Input.y); 
    
    return(Result);
}

WorldToTilePos :: proc(InputPosition : f32) -> f32
{
    Result : f32 = math.floor_f32(InputPosition / TILE_SIZE);
    return(Result);
}

V2WorldToTilePos :: proc(InputPosition : vec2) -> vec2
{
    Result : vec2 = 0;
    Result.x = WorldToTilePos(InputPosition.x);
    Result.y = WorldToTilePos(InputPosition.y);
    return(Result);
}

TileToWorldPos :: proc(Input : f32) -> f32
{
    return((Input * TILE_SIZE));
}

V2TileToWorldPos :: proc(Input : vec2) -> vec2
{
    Result : vec2 = 0;
    Result.x = TileToWorldPos(Input.x);
    Result.y = TileToWorldPos(Input.y);

    return(Result);
}

main :: proc()
{
    State : state = {};
    Delta_t : f32 = {};

    State.WindowSize = {0, 0, 1280, 720};
    rl.InitWindow(State.WindowSize.z, State.WindowSize.w, "HELLO WINDOW");
    rl.SetWindowState({.WINDOW_RESIZABLE});

    LoadData(&State);

    Player : ^entity = CreateEntity(.PLAYER, &State);
    SetupPlayer(Player, &State);

    for RockIndex : u32 = 0; RockIndex < 200; RockIndex += 1
    {
        Rock : ^entity = CreateEntity(.ROCK, &State);
        SetupRock(Rock, &State);
        Rock.Position = {rand.float32_range(-400, 400), rand.float32_range(-400, 400)};
        Rock.Position = vec2{TileToWorldPos(WorldToTilePos(Rock.Position.x)) - (TILE_SIZE * 0.5), TileToWorldPos(WorldToTilePos(Rock.Position.y))};
    }

    for TreeIndex : u32 = 0; TreeIndex < 200; TreeIndex += 1
    {
        Tree : ^entity = CreateEntity(.TREE00, &State);
        SetupTree(Tree, &State);
        Tree.Position = {rand.float32_range(-400, 400), rand.float32_range(-400, 400)};
        Tree.Position = vec2{TileToWorldPos(WorldToTilePos(Tree.Position.x)) - (TILE_SIZE * 0.5), TileToWorldPos(WorldToTilePos(Tree.Position.y))};
    }

    Camera : rl.Camera2D;
    Camera.zoom = 5.3;

    Accumulator : f32 = {};
    for(!rl.WindowShouldClose())
    {
        using State;
        MousePos : vec2 = rl.GetScreenToWorld2D(rl.GetMousePosition(), Camera);

        Camera.offset = {f32(rl.GetScreenWidth()) * 0.5, f32(rl.GetScreenHeight()) * 0.5};
        
        Delta_t = rl.GetFrameTime();
        if(Accumulator >= UPDATE_RATE)
        {
            Accumulator = 0;
        }

        // NOTE(Sleepster): Rendering, We unfortunately have to break it out into smaller functions because Raylib won't let us use the depth buffer 
        {
            rl.BeginDrawing();
            rl.ClearBackground(rl.DARKGRAY);
            rl.BeginMode2D(Camera);

            PlayerTilePosition : ivec2 = ivec2{i32(WorldToTilePos(State.World.Players[0].Position.x)), i32(WorldToTilePos(State.World.Players[0].Position.y))};
            TileRadius : ivec2 = {40, 30};
            for GridX := PlayerTilePosition.x - TileRadius.x; GridX < PlayerTilePosition.x + TileRadius.x; GridX += 1
            {
                for GridY := PlayerTilePosition.y - TileRadius.y; GridY < PlayerTilePosition.y + TileRadius.y; GridY += 1
                {
                    if((GridX + (GridY % 2 == 0)) % 2 == 0)
                    {
                        TilePos : vec2 = {f32(GridX * TILE_SIZE), f32(GridY * TILE_SIZE)};
                        rl.DrawRectangleV(TilePos, vec2{TILE_SIZE, TILE_SIZE}, rl.GRAY);
                    }
                }
            }

            rl.DrawRectangleV(vec2{TileToWorldPos(WorldToTilePos(MousePos.x)), TileToWorldPos(WorldToTilePos(MousePos.y))}, vec2{TILE_SIZE, TILE_SIZE}, rl.RED);
            UpdateRocks(&State, MousePos);
            UpdateTrees(&State, MousePos);
            UpdatePlayers(&State, &Camera, Delta_t);

            rl.EndMode2D();
            rl.EndDrawing();
        }
        Accumulator += Delta_t;
    }
}
