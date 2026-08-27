const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 3000;
const wss = new WebSocketServer({ port: PORT });

// rooms[code] = [{ id, name, ws }]
const rooms = {};
let nextId = 1;

wss.on("connection", (ws) => {
  const clientId = nextId++;
  let roomCode = null;

  ws.on("message", (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }

    switch (msg.type) {
      case "create_room": {
        const code = msg.room;
        if (rooms[code]) {
          send(ws, { type: "error", message: "Room already exists" });
          return;
        }
        roomCode = code;
        rooms[code] = [{ id: clientId, name: msg.name, ws }];
        send(ws, { type: "welcome", id: clientId, room: code });
        break;
      }

      case "join_room": {
        const code = msg.room;
        if (!rooms[code]) {
          send(ws, { type: "error", message: "Room not found" });
          return;
        }
        if (rooms[code].length >= 2) {
          send(ws, { type: "error", message: "Room is full" });
          return;
        }
        roomCode = code;
        const existing = rooms[code][0];
        rooms[code].push({ id: clientId, name: msg.name, ws });
        // Новый игрок получает welcome
        send(ws, { type: "welcome", id: clientId, room: code });
        // Хост узнаёт о новом игроке
        send(existing.ws, { type: "peer_joined", id: clientId, name: msg.name });
        // Новый игрок узнаёт о хосте
        send(ws, { type: "peer_joined", id: existing.id, name: existing.name });
        break;
      }

      case "offer":
      case "answer":
      case "ice": {
        const target = findPeer(roomCode, msg.to);
        if (target) send(target.ws, { type: msg.type, from: clientId, data: msg.data });
        break;
      }
    }
  });

  ws.on("close", () => {
    if (!roomCode || !rooms[roomCode]) return;
    rooms[roomCode] = rooms[roomCode].filter((p) => p.id !== clientId);
    // Уведомляем оставшихся
    for (const peer of rooms[roomCode]) {
      send(peer.ws, { type: "peer_left", id: clientId });
    }
    if (rooms[roomCode].length === 0) delete rooms[roomCode];
  });
});

function send(ws, msg) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

function findPeer(code, id) {
  return rooms[code]?.find((p) => p.id === id) ?? null;
}

console.log(`Signaling server running on port ${PORT}`);
