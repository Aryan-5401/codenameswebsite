module Api exposing
    ( Client
    , Event
    , GameState
    , Index
    , Update
    , chat
    , endTurn
    , index
    , init
    , longPollEvents
    , maybeMakeGame
    , ping
    , submitGuess
    )

import Color exposing (Color)
import Http
import Json.Decode as D
import Json.Encode as E
import Player exposing (Player)
import Side exposing (Side)
import Url
import Array

init : Url.Url -> Client
init url =
    let
        baseUrl =
            case url.host of
                "localhost" ->
                    { url | port_ = Just 8080, path = "", query = Nothing, fragment = Nothing }

                "https://aryan-5401.github.io/codenameswebsite" ->
                    -- TODO: Avoid hardcoding any specific hostnames.
                    { url | host = "https://aryan-5401.github.io/codenameswebsite", path = "", query = Nothing, fragment = Nothing }

                _ ->
                    { url | host = "codenamesgreen.herokuapp.com", path = "", query = Nothing, fragment = Nothing }
    in
    { baseUrl = baseUrl }


type alias Client =
    { baseUrl : Url.Url
    }


type alias GameState =
    { id : String
    , seed : String
    , words : List String
    , events : List Event
    , oneLayout : List Color
    , twoLayout : List Color
    }


type alias Event =
    { number : Int
    , typ : String
    , playerId : String
    , name : String
    , side : Maybe Side
    , index : Int
    , message : Array.Array String
    , num_target_words : Int
    }


type alias Update =
    { seed : String
    , events : List Event
    }


type alias Index =
    { autogeneratedId : String
    }


endpointUrl : Url.Url -> String -> String
endpointUrl baseUrl path =
    { baseUrl | path = path }
        |> Url.toString


index : Client -> (Result Http.Error Index -> msg) -> Cmd msg
index client toMsg =
    Http.post
        { url = endpointUrl client.baseUrl "/index"
        , body = Http.jsonBody (E.object [])
        , expect = Http.expectJson toMsg decodeIndex
        }


submitGuess :
    { gameId : String
    , seed : String
    , player : Player
    , index : Int
    , lastEventId : Int
    , toMsg : Result Http.Error Update -> msg
    , client : Client
    }
    -> Cmd msg
submitGuess r =
    Http.post
        { url = endpointUrl r.client.baseUrl "/guess"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "game_id", E.string r.gameId )
                    , ( "seed", E.string r.seed )
                    , ( "index", E.int r.index )
                    , ( "player_id", E.string r.player.user.id )
                    , ( "name", E.string r.player.user.name )
                    , ( "team", Side.encodeMaybe r.player.side )
                    , ( "last_event", E.int r.lastEventId )
                    ]
                )
        , expect = Http.expectJson r.toMsg decodeUpdate
        }


ping :
    { gameId : String
    , seed : String
    , player : Player
    , toMsg : Result Http.Error () -> msg
    , client : Client
    }
    -> Cmd msg
ping r =
    Http.post
        { url = endpointUrl r.client.baseUrl "/ping"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "game_id", E.string r.gameId )
                    , ( "seed", E.string r.seed )
                    , ( "player_id", E.string r.player.user.id )
                    , ( "name", E.string r.player.user.name )
                    , ( "team", Side.encodeMaybe r.player.side )
                    ]
                )
        , expect = Http.expectWhatever r.toMsg
        }


endTurn :
    { gameId : String
    , seed : String
    , player : Player
    , toMsg : Result Http.Error () -> msg
    , client : Client
    }
    -> Cmd msg
endTurn r =
    Http.post
        { url = endpointUrl r.client.baseUrl "/end-turn"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "game_id", E.string r.gameId )
                    , ( "seed", E.string r.seed )
                    , ( "player_id", E.string r.player.user.id )
                    , ( "name", E.string r.player.user.name )
                    , ( "team", Side.encodeMaybe r.player.side )
                    ]
                )
        , expect = Http.expectWhatever r.toMsg
        }


chat :
    { gameId : String
    , seed : String
    , player : Player
    , toMsg : Result Http.Error () -> msg
    , message : Array.Array String
    , client : Client
    , num_target_words : Int
    }
    -> Cmd msg
chat r =
    Http.post
        { url = endpointUrl r.client.baseUrl "/chat"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "game_id", E.string r.gameId )
                    , ( "seed", E.string r.seed )
                    , ( "player_id", E.string r.player.user.id )
                    , ( "name", E.string r.player.user.name )
                    , ( "team", Side.encodeMaybe r.player.side )
                    , ( "message", E.array E.string r.message )
                    , ( "num_target_words", E.int r.num_target_words)
                    ]
                )
        , expect = Http.expectWhatever r.toMsg
        }


longPollEvents :
    { gameId : String
    , seed : String
    , player : Player
    , lastEventId : Int
    , tracker : String
    , toMsg : Result Http.Error Update -> msg
    , client : Client
    }
    -> Cmd msg
longPollEvents r =
    Http.request
        { method = "POST"
        , headers = []
        , url = endpointUrl r.client.baseUrl "/events"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "game_id", E.string r.gameId )
                    , ( "seed", E.string r.seed )
                    , ( "player_id", E.string r.player.user.id )
                    , ( "name", E.string r.player.user.name )
                    , ( "team", Side.encodeMaybe r.player.side )
                    , ( "last_event", E.int r.lastEventId )
                    ]
                )
        , expect = Http.expectJson r.toMsg decodeUpdate
        , timeout = Just 45000
        , tracker = Just r.tracker
        }


maybeMakeGame :
    { name: String
    , playerId: String
    , prevSeed : Maybe String
    , toMsg : Result Http.Error GameState -> msg
    , client : Client
    }
    -> Cmd msg
maybeMakeGame r =
    Http.post
        { url = endpointUrl r.client.baseUrl "/new-game"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "name", E.string r.name ) 
                    , ( "player_id", E.string r.playerId )
                    , ( "prev_seed"
                      , case r.prevSeed of
                            Nothing ->
                                E.null

                            Just seed ->
                                E.string seed
                      )
                    ]
                )
        , expect = Http.expectJson r.toMsg (decoderGameState)
        }


decodeIndex : D.Decoder Index
decodeIndex =
    D.map Index (D.field "autogenerated_id" D.string)


decoderGameState : D.Decoder GameState
decoderGameState =
    D.map6 GameState
        (D.field "game_id" D.string)
        (D.field "state" (D.field "seed" D.string))
        (D.field "words" (D.list D.string))
        (D.field "state" (D.field "events" (D.list decodeEvent)))
        (D.field "one_layout" (D.list Color.decode))
        (D.field "two_layout" (D.list Color.decode))


decodeUpdate : D.Decoder Update
decodeUpdate =
    D.map2 Update
        (D.field "seed" D.string)
        (D.field "events" (D.list decodeEvent))


decodeEvent : D.Decoder Event
decodeEvent =
    D.map8 Event
        (D.field "number" D.int)
        (D.field "type" D.string)
        (D.field "player_id" D.string)
        (D.field "name" D.string)
        (D.field "team" Side.decodeMaybe)
        (D.field "index" D.int)
        (D.oneOf 
            [
                D.field "message" (D.array D.string)
                , D.succeed (Array.repeat 6 "")
            ]
        )
        (D.field "num_target_words" D.int)
        
