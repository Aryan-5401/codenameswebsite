port module User exposing (User, decode, store)

import Json.Decode as D
import Json.Encode as E


port storeCache : E.Value -> Cmd msg


{-| A user holds persisted user preferences.

It's stored in local storage, and is used to
keep settings like the player's name between
sessions.

-}
type alias User =
    { id : String
    , name : String
    , country: String
    , gender: String
    , age: String
    }


store : User -> Cmd msg
store user =
    user
        |> encode
        |> storeCache


decode : D.Value -> Result D.Error User
decode value =
    D.decodeValue D.string value
        |> Result.andThen (D.decodeString decoder)


encode : User -> E.Value
encode user =
    E.object
        [ ( "player_id", E.string user.id )
        , ( "name", E.string user.name )
        , ( "country", E.string user.name )
        , ( "gender", E.string user.name )
        , ( "name", E.string user.name )
        ]


decoder : D.Decoder User
decoder =
    D.map5 User
        (D.field "player_id" D.string)
        (D.field "name" D.string)
        (D.field "country" D.string)
        (D.field "gender" D.string)
        (D.field "age" D.string)
