# Non-HTTP Protocols

This file covers WebSocket, MQTT, and JMS — loaded when the user works with
protocols beyond HTTP/REST. HTTP is already covered in SKILL.md.

> **Edition requirements:**
> | Protocol | Community Edition | Enterprise Edition |
> |---|---|---|
> | HTTP/REST | ✅ Free | ✅ |
> | WebSocket | ✅ Free | ✅ |
> | MQTT | ❌ Not available | ✅ Paid |
> | JMS | ❌ Not available | ✅ Paid |
>
> Always inform the user if they ask for MQTT or JMS that these require a
> **Gatling Enterprise license**. Direct them to https://gatling.io/enterprise
> if they want to evaluate. For IoT load testing on Community Edition,
> recommend HTTP-based alternatives (REST APIs over the MQTT broker's HTTP interface).

---

## WebSocket

No extra dependency needed — bundled in `gatling-charts-highcharts`.

```java
// Protocol
HttpProtocolBuilder protocol = http
    .baseUrl("https://api.example.com")
    .wsBaseUrl("wss://ws.example.com");

// Scenario
ScenarioBuilder scn = scenario("WebSocket")
    // Authenticate over HTTP first, then open WS
    .exec(http("Login").post("/auth/login")
        .check(jsonPath("$.token").saveAs("token")))
    .exec(ws("Connect").connect("/chat")
        .header("Authorization", "Bearer #{token}"))
    .pause(1)
    // Send and wait for correlated response
    .exec(ws("Send")
        .sendText("""{"type":"msg","text":"hello #{username}"}""")
        .await(Duration.ofSeconds(5)).on(   // always specify unit explicitly
            ws.checkTextMessage("Ack")
                .check(jsonPath("$.type").is("msg"))
        ))
    .pause(2)
    .exec(ws("Close").close());
```

**Common mistake:** Forgetting to close the WebSocket — always add `.exec(ws("Close").close())` at the end of the scenario.

---

## MQTT

### Extra Maven dependency

```xml
<dependency>
  <groupId>io.gatling</groupId>
  <artifactId>gatling-mqtt</artifactId>
  <version>3.14.5</version>
  <scope>test</scope>
</dependency>
```

### Extra Gradle dependency

```groovy
gatling 'io.gatling:gatling-mqtt:3.14.5'
```

```java
// Protocol — plain TCP
MqttProtocolBuilder protocol = mqtt
    .broker("broker.example.com", 1883)
    .clientId("gatling-#{userId}")
    .cleanSession(true)
    .correlateBy(jmesPath("id"));   // match request/response by field

// Protocol — TLS
MqttProtocolBuilder tlsProtocol = mqtt
    .broker("broker.example.com", 8883)
    .useTls(true)
    .clientId("gatling-#{userId}")
    .correlateBy(jmesPath("id"));

// Scenario
ScenarioBuilder scn = scenario("MQTT Pub/Sub")
    .exec(mqtt("Connect").connect())
    .exec(mqtt("Subscribe")
        .subscribe("devices/#{deviceId}/response")
        .qosAtLeastOnce())
    .exec(mqtt("Publish")
        .publish("devices/#{deviceId}/command")
        .message(StringBody("""{"id":"#{requestId}","cmd":"status"}"""))
        .qosAtLeastOnce()
        .await(Duration.ofSeconds(5)).on(   // always specify unit explicitly
            mqtt.checkForTopic("devices/#{deviceId}/response")
                .check(jmesPath("cmd").is("status"))
        ))
    .exec(mqtt("Disconnect").disconnect());
```

**QoS levels:**
- `.qosAtMostOnce()` — QoS 0, fire and forget, highest throughput
- `.qosAtLeastOnce()` — QoS 1, at least once delivery (most common)
- `.qosExactlyOnce()` — QoS 2, exactly once, lowest throughput

**Common mistake:** Not calling `.correlateBy()` on the protocol when using `await()` — without it, response matching fails silently.

---

## JMS

### Extra Maven dependency

```xml
<dependency>
  <groupId>io.gatling</groupId>
  <artifactId>gatling-jms</artifactId>
  <version>3.14.5</version>
  <scope>test</scope>
</dependency>
<!-- Add your JMS provider (e.g. ActiveMQ) -->
<dependency>
  <groupId>org.apache.activemq</groupId>
  <artifactId>activemq-client</artifactId>
  <version>5.18.3</version>
  <scope>test</scope>
</dependency>
```

```java
// Protocol
JmsProtocolBuilder protocol = jms
    .connectionFactory(new ActiveMQConnectionFactory("tcp://localhost:61616"))
    .credentials("admin", "admin")
    .usePersistentDeliveryMode();

// Scenario — request/reply
ScenarioBuilder scn = scenario("JMS")
    .exec(jms("Send Order")
        .requestReply()
        .queue("orders.request")
        .replyQueue("orders.reply")
        .textMessage("""{"orderId":"#{orderId}","item":"#{item}"}""")
        .check(xpath("/order/status").saveAs("status")));

// Fire-and-forget (no reply) — must be part of a ScenarioBuilder chain
ScenarioBuilder auditScn = scenario("JMS Audit")
    .exec(jms("Publish Event")
        .send()
        .queue("events.audit")
        .textMessage("""{"event":"login","user":"#{username}"}"""));
```

---

## Protocol Selection

| Protocol | Use when |
|---|---|
| HTTP/REST | Web APIs, microservices — default choice |
| WebSocket | Real-time: chat, live dashboards, notifications |
| MQTT | IoT devices, sensor telemetry at scale |
| JMS | Enterprise queues: order processing, audit logs |
