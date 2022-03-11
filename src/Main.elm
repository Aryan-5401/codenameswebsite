module Main exposing (Model, Msg(..), init, main, update, view)

import Api
import Browser
import Browser.Navigation as Nav
import Dict
import Game
import Array
import Html exposing (Html, a, button, div, form, h1, h2, h3, i, input, label, p, span, strong, text)
import Html.Attributes as Attr
import Html.Events exposing (onBlur, onClick, onInput, onSubmit)
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Http
import Json.Decode
import Loading exposing (LoaderType(..), defaultConfig)
import Side
import Url
import Url.Builder as UrlBuilder
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, string, top)
import Url.Parser.Query as Query
import User
import Array

---- MODEL ----


type alias Model =
    { key : Nav.Key
    , user : User.User
    , page : Page
    , apiClient : Api.Client
    }


type Page
    = NotFound
    | Error String
    | Home String
    | GameLoading String
    | GameInProgress Game.Model (Array.Array String) GameView


type GameView
    = ShowDefault
    | ShowSettings Settings


type alias Settings =
    { name : String }


init : Json.Decode.Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init encodedUser url key =
    case User.decode encodedUser of
        Err e ->
            ( { key = key
              , user = User.User "" "" "" "" ""
              , page = Error (Json.Decode.errorToString e)
              , apiClient = Api.init url
              }
            , Cmd.none
            )

        Ok user ->
            stepUrl url
                { key = key
                , user = user
                , page = Home ""
                , apiClient = Api.init url
                }



---- UPDATE ----


type Msg
    = NoOp
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | IndexData (Result Http.Error Api.Index)
    | IdChanged String
    | SubmitNewGame
    | NextGame
    | PickSide Side.Side
    | GameUpdate Game.Msg
    | GotGame (Result Http.Error Api.GameState)
    | ChatMessageChanged (Array.Array String)
    | SendChat
    | ToggleSettings
    | SettingsEdit (Settings -> Settings)
    | SaveSettings Settings


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( LinkClicked urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                Browser.External href ->
                    ( model
                    , Nav.load href
                    )

        ( UrlChanged url, _ ) ->
            stepUrl url model

        ( IndexData (Ok data), Home id ) ->
            ( if id == "" then
                { model | page = Home data.autogeneratedId }

              else
                model
            , Cmd.none
            )

        ( IdChanged id, Home _ ) ->
            ( { model | page = Home id }, Cmd.none )

        -- ( SubmitNewGame, Home id ) ->
        --     ( model, Nav.pushUrl model.key (UrlBuilder.relative [ id ] []) )

        ( SubmitNewGame, _ ) ->
            ( model, Api.maybeMakeGame
            { name = model.user.name
            , playerId = model.user.id
            , prevSeed = Nothing
            , toMsg = GotGame
            , client = model.apiClient
            } ) 

        ( NextGame, GameInProgress game _ _ ) ->
            stepGameView model game.id (Just game.seed)

        ( GameUpdate gameMsg, GameInProgress game chat gameView ) ->
            case Game.update gameMsg game GameUpdate of
                Just ( newGame, gameCmd ) ->
                    ( { model | page = GameInProgress newGame chat gameView }, gameCmd )

                Nothing ->
                    stepGameView model game.id Nothing

        ( GotGame (Ok state), GameInProgress old chat _ ) ->
            let
                ( gameModel, gameCmd ) =
                    Game.init state model.user model.apiClient GameUpdate
            in
            ( { model | page = GameInProgress gameModel chat ShowDefault }, gameCmd )

        ( GotGame (Ok state), Home id ) ->
            let
                ( gameModel, gameCmd ) =
                    Game.init state model.user model.apiClient GameUpdate
            in
            ( { model | page = GameInProgress gameModel (Array.repeat 6 "")  ShowDefault }, gameCmd )

        ( GotGame (Ok state), GameLoading id ) ->
            let
                ( gameModel, gameCmd ) =
                    Game.init state model.user model.apiClient GameUpdate
            in
            ( { model | page = GameInProgress gameModel (Array.repeat 6 "") ShowDefault }, gameCmd )

        ( PickSide side, GameInProgress oldGame chat gameView ) ->
            let
                oldPlayer =
                    oldGame.player

                game =
                    { oldGame | player = { oldPlayer | side = Just side } }
            in
            ( { model | page = GameInProgress game chat gameView }
            , Api.ping
                -- Pinging will immediately record the change on the
                -- server, without having to wait for the long
                -- poll to make a new request.
                { gameId = game.id
                , seed = game.seed
                , player = game.player
                , toMsg = always NoOp
                , client = model.apiClient
                }
            )

        ( ChatMessageChanged message, GameInProgress g _ gameView ) ->
            ( { model | page = GameInProgress g message gameView }, Cmd.none )

        ( SendChat, GameInProgress g message gameView ) ->
            ( { model | page = GameInProgress g (Array.repeat 6 "") gameView }
            , Api.chat
                { gameId = g.id
                , seed = g.seed
                , player = g.player
                , toMsg = always NoOp
                , message = message
                , client = model.apiClient
                }
            )

        ( ToggleSettings, GameInProgress g message gameView ) ->
            case gameView of
                ShowSettings _ ->
                    ( { model | page = GameInProgress g message ShowDefault }, Cmd.none )

                ShowDefault ->
                    ( { model | page = GameInProgress g message (ShowSettings { name = g.player.user.name }) }, Cmd.none )

        ( SettingsEdit editSetting, GameInProgress g message (ShowSettings settings) ) ->
            ( { model | page = GameInProgress g message (ShowSettings (editSetting settings)) }, Cmd.none )

        ( GotGame (Err e), _ ) ->
            -- TODO: display an error message
            ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


stepUrl : Url.Url -> Model -> ( Model, Cmd Msg )
stepUrl url model =
    case Maybe.withDefault NullRoute (Parser.parse route url) of
        NullRoute ->
            ( { model | page = NotFound }, Cmd.none )

        Index ->
            ( { model | page = Home "" }, Api.index model.apiClient IndexData )

        GameView id ->
            stepGameView model id Nothing


stepGameView : Model -> String -> Maybe String -> ( Model, Cmd Msg )
stepGameView model id prevSeed =
    ( { model | page = GameLoading id }
    , Api.maybeMakeGame
        { name = model.user.name
        , playerId = model.user.id
        , prevSeed = prevSeed
        , toMsg = GotGame
        , client = model.apiClient
        }
    )


type Route
    = NullRoute
    | Index
    | GameView String


route : Parser (Route -> a) a
route =
    oneOf
        [ map Index top
        , map GameView string
        ]



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    case model.page of
        NotFound ->
            viewNotFound

        Home id ->
            viewHome id

        GameLoading id ->
            { title = "Codenames Green"
            , body = viewGameLoading id
            }

        GameInProgress game chat gameView ->
            viewGameInProgress game chat gameView

        Error msg ->
            viewError msg


viewNotFound : Browser.Document Msg
viewNotFound =
    div [ Attr.id "not-found" ]
        [ h2 [] [ text "Page not found" ]
        , p []
            [ text "That page doesn't exist. "
            , a [ Attr.href "/" ] [ text "Go to the homepage" ]
            ]
        ]
        |> viewLayout (Just "Page not found")


viewLayout : Maybe String -> Html Msg -> Browser.Document Msg
viewLayout subtitle content =
    { title =
        case subtitle of
            Just t ->
                "Codenames Green | " ++ t

            Nothing ->
                "Codenames Green"
    , body =
        [ div [ Attr.id "layout" ]
            [ viewHeader
            , div [ Attr.id "content" ] [ content ]
            ]
        ]
    }


viewError : String -> Browser.Document Msg
viewError msg =
    div [ Attr.id "error" ]
        [ h2 [] [ text "Oops" ]
        , p []
            [ text "An unexpected error was encountered. Most likely this is the result of corrupted local storage. Try clearing all storage associated with the app." ]
        , p [] [ strong [] [ text "Error: " ], text msg ]
        ]
        |> viewLayout (Just "Error")


viewGameInProgress : Game.Model -> (Array.Array String) -> GameView -> Browser.Document Msg
viewGameInProgress g chatMessage gameView =
    div [ Attr.id "game" ]
        [ Html.map GameUpdate (Game.viewBoard g)
        , div [ Attr.id "sidebar" ] (viewSidebar g chatMessage gameView)
        ]
        |> viewLayout Nothing


viewSidebar : Game.Model -> Array.Array String -> GameView -> List (Html Msg)
viewSidebar g chatMessage gameView =
    let
        sides =
            Dict.values g.players

        playersOnSideA =
            sides
                |> List.filter (\x -> x == Side.A)
                |> List.length

        playersOnSideB =
            sides
                |> List.filter (\x -> x == Side.B)
                |> List.length
    in
    case ( g.player.side, gameView ) of

    -- this pattern-match won't run!
        ( Nothing, _ ) ->
            [ viewJoinASide playersOnSideA playersOnSideB ]

        ( _, ShowSettings settings ) ->
            viewSettings g settings

        ( Just side, ShowDefault ) ->
            viewActiveSidebar g side chatMessage


viewSettings : Game.Model -> Settings -> List (Html Msg)
viewSettings g settings =
    [ div [ Attr.id "settings" ]
        [ div []
            [ i
                [ Attr.class "icon ion-ios-arrow-back icon-button back-button"
                , onClick ToggleSettings
                ]
                []
            , div [ Attr.class "setting" ]
                [ label [ Attr.for "settings-player-name" ] [ text "Your name" ]
                , input
                    [ Attr.value settings.name
                    , onInput (\x -> SettingsEdit (\s -> { s | name = x }))
                    , onBlur (SaveSettings settings)
                    ]
                    []
                ]
            ]
        ]
    ]


viewActiveSidebar : Game.Model -> Side.Side -> Array.Array String -> List (Html Msg)
viewActiveSidebar g side chatMessage =
    [ Html.map GameUpdate (lazy Game.viewStatus g)
    , Html.map GameUpdate (lazy2 Game.viewKeycard g side)
    , lazy3 viewEventBox g side chatMessage
    , viewButtonRow
    ]

getSubChat : Int -> Array.Array String -> String
getSubChat idx messageArray =
    Maybe.withDefault "" (Array.get idx messageArray)

setField : Int -> Array.Array String -> String -> Msg
setField idx messageArray message =
    ChatMessageChanged (Array.set idx message messageArray)

viewEventBox : Game.Model -> Side.Side -> Array.Array String -> Html Msg
viewEventBox g side chatMessage =
    div [ Attr.id "event-log" ]
        [ Html.map GameUpdate (Game.viewEvents g)
        , form [ Attr.id "chat-form", onSubmit SendChat ]
            [ div [] [ text "Clue " , input [ Attr.value (getSubChat 0 chatMessage), onInput (setField 0 chatMessage) ] [] ]
            , div [] [ text "Target " , input [ Attr.value (getSubChat 1 chatMessage), onInput (setField 1 chatMessage) ] [] ]
            , div [] [ text "Target " , input [ Attr.value (getSubChat 2 chatMessage), onInput (setField 2 chatMessage) ] [] ]
            , div [] [ text "Target " , input [ Attr.value (getSubChat 3 chatMessage), onInput (setField 3 chatMessage) ] [] ]
            , div [] [ text "Target " , input [ Attr.value (getSubChat 4 chatMessage), onInput (setField 4 chatMessage) ] [] ]
            , div [] [ text "Target " , input [ Attr.value (getSubChat 5 chatMessage), onInput (setField 5 chatMessage) ] [] ]
            , button [] [ text "Send" ]
            ]
        ]


viewButtonRow : Html Msg
viewButtonRow =
    div [ Attr.id "button-row" ]
        [ div [] [ ]

        -- TODO: add settings
        -- , div [] [ i [ Attr.id "open-settings", Attr.class "icon icon-button ion-ios-settings", onClick ToggleSettings ] [] ]
        ]


viewJoinASide : Int -> Int -> Html Msg
viewJoinASide a b =
    div [ Attr.id "join-a-team" ]
        [ h3 [] [ text "Pick a side" ]
        , p [] [ text "Pick a side to start playing. Each side has a different key card." ]
        , div [ Attr.class "buttons" ]
            [ button [ onClick (PickSide Side.A) ]
                [ span [ Attr.class "call-to-action" ] [ text "A" ]
                , span [ Attr.class "details" ] [ text "(", text (String.fromInt a), text " players)" ]
                ]
            , button [ onClick (PickSide Side.B) ]
                [ span [ Attr.class "call-to-action" ] [ text "B" ]
                , span [ Attr.class "details" ] [ text "(", text (String.fromInt b), text " players)" ]
                ]
            ]
        ]


viewGameLoading : String -> List (Html Msg)
viewGameLoading id =
    [ viewHeader
    , div [ Attr.id "game-loading" ]
        [ Loading.render Circle { defaultConfig | size = 100, color = "#b7ec8a" } Loading.On
        ]
    ]


viewHome : String -> Browser.Document Msg
viewHome id =
    { title = "Codenames Green"
    , body =
        [ div [ Attr.id "home" ]
            [ h1 [] [ text "Codenames" ]
            , p [] [ text "To start a game, click 'Play'." ]
            , form
                [ Attr.id "new-game"
                , onSubmit SubmitNewGame
                ]
                [ button [] [ text "Play" ] ]
            ]
        ]
    }


viewHeader : Html Msg
viewHeader =
    div [ Attr.id "header" ] [ h1 [] [ a [ Attr.href "/" ] [ text "Codenames Green" ] ] ]



---- PROGRAM ----


main : Program Json.Decode.Value Model Msg
main =
    Browser.application
        { view = view
        , init = init
        , update = update
        , subscriptions = always Sub.none
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
