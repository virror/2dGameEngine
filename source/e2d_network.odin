package main

import "core:fmt"
import "core:mem"
import "core:slice"
import steam "../../steamworks"

NO_STEAM :: true
NET_MAX_PLAYERS :i32: 4
NET_TICK_TIME :f32: 0.1

Net_player :: struct {
    id: steam.CSteamID,
    player: ^Entity,
}

@(private="file")
net_lobby_id: u64
@(private="file")
net_tick_counter: f32
net_host_id: u64
net_players: [NET_MAX_PLAYERS]Net_player
net_is_host: bool
//Callbacks
net_on_tick: proc()
net_on_message: proc(data: []u8, user_id: u64)
net_on_lobby_enter: proc(lobby_id: u64)
net_on_lobby_invite: proc(lobby_id: u64, user_id: u64)
net_on_lobby_chat_update: proc(lobby_id: u64, state: u32)

net_init :: proc() {
    if steam.RestartAppIfNecessary(steam.uAppIdInvalid) {
        fmt.println("Launching app through steam...")
        return
    }
    when !NO_STEAM {
        err_msg: steam.SteamErrMsg
        if err := steam.InitFlat(&err_msg); err != .OK {
            fmt.printfln("steam.InitFlat failed with code '{}' and message \"{}\"", err, transmute(cstring)&err_msg[0])
            panic("Steam Init failed. Make sure Steam is running.")
        }
        steam.ManualDispatch_Init()

        if !steam.User_BLoggedOn(steam.User()) {
            panic("User isn't logged in.")
        }
    }
}

net_destroy :: proc() {
    steam.Shutdown()
}

net_reset :: proc() {
    net_lobby_id = 0
    net_tick_counter = 0
    net_host_id = 0
    net_players = {}
    net_is_host = false

    net_on_tick = nil
    net_on_message = nil
    net_on_lobby_enter = nil
    net_on_lobby_invite = nil
    net_on_lobby_chat_update = nil
}

net_update :: proc(dt: f32) {
    net_callbacks()
    when !NO_STEAM {
        net_recieve()
    }
    net_tick_counter += dt
    if net_tick_counter >= NET_TICK_TIME {
        net_tick_counter -= NET_TICK_TIME
        if net_on_tick != nil {
            net_on_tick()
        }
    }
}

@(private="file")
net_recieve :: proc() {
    messages: [10]^steam.SteamNetworkingMessage
    amount := steam.NetworkingMessages_ReceiveMessagesOnChannel(steam.NetworkingMessages_SteamAPI(), 0, &messages[0], len(messages))
    for i in 0..<amount {
        msg_data := slice.bytes_from_ptr(messages[i].pData, int(messages[i].cbSize))
        if net_on_message != nil {
            steam_id := steam.NetworkingIdentity_GetSteamID(&messages[i].identityPeer)
            net_on_message(msg_data, steam_id)
        }
        steam.NetworkingMessage_t_Release(messages[i])
    }
}

@(private="file")
net_callbacks :: proc() {
    temp_mem := make([dynamic]byte, context.temp_allocator)

    steam_pipe := steam.GetHSteamPipe()
    steam.ManualDispatch_RunFrame(steam_pipe)
    callback: steam.CallbackMsg

    for steam.ManualDispatch_GetNextCallback(steam_pipe, &callback) {
        if callback.iCallback == .SteamAPICallCompleted {
            //fmt.println("CallResult: ", callback)
            call_completed := transmute(^steam.SteamAPICallCompleted)callback.pubParam
            resize(&temp_mem, int(callback.cubParam))
            if temp_call_res, ok := mem.alloc(int(callback.cubParam), allocator = context.temp_allocator); ok == nil {
                bFailed: bool
                if steam.ManualDispatch_GetAPICallResult(steam_pipe, call_completed.hAsyncCall, temp_call_res, callback.cubParam, callback.iCallback, &bFailed) {
                    //fmt.println("   call_completed", call_completed)
                    /*if call_completed.iCallback == .NumberOfCurrentPlayers {
                        onGetNumberOfCurrentPlayers(transmute(^steam.NumberOfCurrentPlayers)temp_call_res, bFailed)
                    }*/
                }
            }
        } else {
            //fmt.println("Callback: ", callback)
            #partial switch callback.iCallback {
            case .LobbyEnter:
                net_on_LobbyEnter(callback.pubParam)
            case .LobbyChatUpdate:
                net_on_LobbyChatUpdate(callback.pubParam)
            case .LobbyInvite:
                net_on_LobbyInvite(callback.pubParam)
            case .GameLobbyJoinRequested:
                fmt.println(transmute(^steam.GameLobbyJoinRequested)callback.pubParam)
            case .SteamNetworkingMessagesSessionRequest:
                net_on_SteamNetworkingMessagesSessionRequest(callback.pubParam)
            }
        }
        steam.ManualDispatch_FreeLastCallback(steam_pipe)
    }
}

@(private="file")
net_on_LobbyEnter :: proc(data: ^u8) {
    lobby_data := transmute(^steam.LobbyEnter)data
    lobby_count := steam.Matchmaking_GetNumLobbyMembers(steam.Matchmaking(), lobby_data.ulSteamIDLobby)
    net_lobby_id = lobby_data.ulSteamIDLobby
    net_host_id = steam.Matchmaking_GetLobbyOwner(steam.Matchmaking(), net_lobby_id)

    my_id := steam.User_GetSteamID(steam.User())
    net_players[0].id = my_id
    if lobby_count != 1 {
        for i in 0..<lobby_count {
            id := steam.Matchmaking_GetLobbyMemberByIndex(steam.Matchmaking(), lobby_data.ulSteamIDLobby, i)
            if id != my_id {
                for j in 1..<len(net_players) {
                    if net_players[j].id == 0 {
                        net_players[j].id = id
                        break
                    }
                }
            }
        }
    }
    if net_on_lobby_enter != nil {
        net_on_lobby_enter(lobby_data.ulSteamIDLobby)
    }
}

@(private="file")
net_on_LobbyChatUpdate :: proc(data: ^u8) {
    lobby_data := transmute(^steam.LobbyChatUpdate)data

    for j in 1..<len(net_players) {
        if net_players[j].id == 0 {
            net_players[j].id = lobby_data.ulSteamIDUserChanged
            break
        }
    }

    if net_on_lobby_chat_update != nil {
        net_on_lobby_chat_update(lobby_data.ulSteamIDUserChanged, lobby_data.rgfChatMemberStateChange)
    }
}

@(private="file")
net_on_LobbyInvite :: proc(data: ^u8) {
    lobby_data := transmute(^steam.LobbyInvite)data
    if net_on_lobby_invite != nil {
        net_on_lobby_invite(lobby_data.ulSteamIDLobby, lobby_data.ulSteamIDUser)
    }
}

@(private="file")
net_on_SteamNetworkingMessagesSessionRequest :: proc(data: ^u8) {
    req_data := transmute(^steam.SteamNetworkingMessagesSessionRequest)data
    remote_id := steam.NetworkingIdentity_GetSteamID(&req_data.identityRemote)
    for i in 1..<NET_MAX_PLAYERS {
        if remote_id == net_players[i].id {
            steam.NetworkingMessages_AcceptSessionWithUser(steam.NetworkingMessages_SteamAPI(), &req_data.identityRemote)
            break
        }
    }
}

net_lobby_create :: proc(type: steam.ELobbyType) {
    when !NO_STEAM {
        steam.Matchmaking_CreateLobby(steam.Matchmaking(), type, NET_MAX_PLAYERS)
    }
    net_is_host = true
}

net_lobby_join :: proc(lobby_id: steam.CSteamID) {
    steam.Matchmaking_JoinLobby(steam.Matchmaking(), lobby_id)
    net_lobby_id = lobby_id
}

net_lobby_destroy :: proc() {
    when !NO_STEAM {
        steam.Matchmaking_LeaveLobby(steam.Matchmaking(), net_lobby_id)
    }
}

net_show_invite :: proc() {
    when !NO_STEAM {
        steam.Friends_ActivateGameOverlayInviteDialog(steam.Friends(), net_lobby_id)
    }
}

net_get_user_name :: proc(id: u64) -> string {
    when !NO_STEAM {
        return string(steam.Friends_GetFriendPersonaName(steam.Friends(), id))
    } else {
        return "Player"
    }
}

net_send :: proc(data: []u8, reliable: bool) {
    flag: i32
    if reliable {
        flag = 8
    }
    for i in 1..<NET_MAX_PLAYERS {
        if net_players[i].id != 0 {
            id: steam.SteamNetworkingIdentity
            steam.NetworkingIdentity_SetSteamID(&id, net_players[i].id)
            steam.NetworkingMessages_SendMessageToUser(steam.NetworkingMessages_SteamAPI(), &id, raw_data(data), u32(len(data)), flag, 0)
        }
    }
}