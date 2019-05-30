port module Main exposing (..)

-- import Debug exposing (log)
import Browser
import Html exposing (Html, text, div, h1, img, button)
import Cmd.Extra exposing (withCmd, withNoCmd)
import Dict exposing (Dict)
import Html.Attributes exposing (src)
import Json.Encode exposing (Value)
import Html.Events exposing (onClick)
import PortFunnel exposing (FunnelSpec, GenericMessage, ModuleDesc, StateAccessors)
import PortFunnel.Geolocation as Geolocation
    exposing
        ( Message
        , Movement(..)
        , Response(..)
        )
import Http
import Json.Decode exposing (Decoder, field, string)

---- MODEL ----

port cmdPort : Value -> Cmd msg

port subPort : (Value -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions model =
    subPort Process

type alias FunnelState =
    { geolocation : Geolocation.State }

type alias Model =
    { city : Maybe String
    , location : Maybe Geolocation.Location
    , state : FunnelState
    }


init : ( Model, Cmd Msg )
init =
    let
        model = { city = Nothing
                , location = Nothing
                , state = { geolocation = Geolocation.initialState }
                }
    in
        update GetGeoLocation model


---- UPDATE ----


type Msg
    = GetGeoLocation
    | Process Value
    | ReverseGeoResult (Result Http.Error String)

send : Message -> Cmd Msg
send message =
    Geolocation.send cmdPort message

geolocationAccessors : StateAccessors FunnelState Geolocation.State
geolocationAccessors =
    StateAccessors .geolocation (\substate state -> { state | geolocation = substate })


type alias AppFunnel substate message response =
    FunnelSpec FunnelState substate message response Model Msg


type Funnel
    = GeolocationFunnel (AppFunnel Geolocation.State Geolocation.Message Geolocation.Response)


funnels : Dict String Funnel
funnels =
    Dict.fromList
        [ ( Geolocation.moduleName
          , GeolocationFunnel <|
                FunnelSpec geolocationAccessors
                    Geolocation.moduleDesc
                    Geolocation.commander
                    geolocationHandler
          )
        ]


geolocationHandler : Geolocation.Response -> FunnelState -> Model -> ( Model, Cmd Msg )
geolocationHandler response state model =
    case response of
        LocationResponse location ->

            { model
                | location = Just location
            }
                |> withNoCmd

        ErrorResponse error ->
            model
            |> withNoCmd

        _ ->
            update GetGeoLocation model

appTrampoline : GenericMessage -> Funnel -> FunnelState -> Model -> Result String ( Model, Cmd Msg )
appTrampoline genericMessage funnel state model =
    case funnel of
        GeolocationFunnel geolocationFunnel ->
            PortFunnel.appProcess cmdPort
                genericMessage
                geolocationFunnel
                state
            model

reqReverseGeoLookup : Geolocation.Location -> Cmd Msg
reqReverseGeoLookup location =
    let
        lat = String.fromFloat location.latitude
        lon = String.fromFloat location.longitude
        url = String.join
            ""
            [
              "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat="
            , lat
            , "&lon="
            , lon
            , "&zoom=18&addressdetails=1&email=havar.novik%40gmail.com"
            ]
    in
        Http.get
            { url = url
            , expect = Http.expectJson ReverseGeoResult reverseGeoLookupDecode
            }


reverseGeoLookupDecode : Decoder String
reverseGeoLookupDecode =
    field "address" (field "town" string)

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GetGeoLocation ->
            model
                |> withCmd
                    (send Geolocation.now)
        Process value ->
            case
                PortFunnel.processValue funnels
                    appTrampoline
                    value
                    model.state
                    model
            of
                Err error ->
                    -- { model | error = Just error } |> withNoCmd
                    ( model, Cmd.none )

                Ok (mdl, cmd) ->
                        case mdl.location of
                        Just location ->
                            (mdl, reqReverseGeoLookup location)
                        _ -> 
                            (mdl, cmd)
        ReverseGeoResult httpRes ->
            case httpRes of
                Err err ->
                    ( model, Cmd.none )
                Ok newCity ->
                    { model | city = Just newCity } |> withNoCmd



---- VIEW ----


view : Model -> Html Msg
view model =
    div []
        [ button
            [ onClick GetGeoLocation ]
            [ text "get" ]
        , h1
          []
          [
            text <| case model.city of
              Just city-> city
              Nothing -> "loading.."
          ]
        ]



---- PROGRAM ----


main : Program () Model Msg
main =
    Browser.element
        { view = view
        , init = \_ -> init
        , update = update
        , subscriptions = subscriptions
        }
