const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8008 });

let pair = []; // 存储当前的连接对，每对连接是一个数组 [ws1, ws2]

wss.on('connection', function connection(ws) {
  console.log('New client connected');

  // 当前连接加入 pair 数组
  pair.push(ws);

  if (pair.length === 2) {
    // 如果 pair 中有两个连接，则它们形成一对，可以开始信令交换
    const [ws1, ws2] = pair;

    // 清空 pair 数组，准备接收下一对连接
    pair = [];



    // 绑定消息处理函数
    ws1.on('message', function incoming(message) {
      let messageString = message;
      if (typeof message !== 'string') {
        // 如果不是字符串，尝试将其转换为 UTF-8 编码的字符串
        messageString = message.toString('utf8');
      }      
      let data = JSON.parse(messageString);
      console.log('Received message from client 1:', data);
      ws2.send(messageString); // 将消息发送给另一个连接
    });

    ws2.on('message', function incoming(message) {
      let messageString = message;
      if (typeof message !== 'string') {
        // 如果不是字符串，尝试将其转换为 UTF-8 编码的字符串
        messageString = message.toString('utf8');
      }      
      let data = JSON.parse(messageString);
      console.log('Received message from client 1:', data);
      ws1.send(messageString); // 将消息发送给另一个连接
    });

    // 处理连接关闭
    ws1.on('close', function close() {
      console.log('Client 1 disconnected');
      ws2.close(); // 关闭另一个连接
    });

    ws2.on('close', function close() {
      console.log('Client 2 disconnected');
      ws1.close(); // 关闭另一个连接
    });
  }
});
