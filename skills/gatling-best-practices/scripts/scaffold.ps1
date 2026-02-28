# scaffold.ps1 — Scaffolds a new Gatling project from scratch (Windows PowerShell).
# Usage: .\scaffold.ps1
# Requires PowerShell 5.1+ or PowerShell Core 7+

param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Fail          { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor White
Write-Host "║   Gatling Project Scaffold           ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor White
Write-Host ""

# ── Prompts ───────────────────────────────────────────────────────────────────
$ProjectName = Read-Host "Project name (e.g. my-perf-tests)"
if (-not $ProjectName) { $ProjectName = "my-perf-tests" }
if ($ProjectName -notmatch '^[a-zA-Z][a-zA-Z0-9_-]*$') {
    Fail "Invalid project name. Use letters, numbers, hyphens, underscores."
}

Write-Host ""
Write-Host "Language:" -ForegroundColor White
Write-Host "  1) Java       (recommended)"
Write-Host "  2) Kotlin"
Write-Host "  3) Scala"
Write-Host "  4) TypeScript"
Write-Host "  5) JavaScript"
$LangChoice = Read-Host "Choice [1]"
if (-not $LangChoice) { $LangChoice = "1" }

$Lang = switch ($LangChoice) {
    "1" { "java" }
    "2" { "kotlin" }
    "3" { "scala" }
    "4" { "typescript" }
    "5" { "javascript" }
    default { Fail "Invalid choice." }
}

if ($Lang -in @("typescript","javascript")) {
    $BuildTool = "npm"
} else {
    Write-Host ""
    Write-Host "Build tool:" -ForegroundColor White
    Write-Host "  1) Maven  (recommended)"
    Write-Host "  2) Gradle"
    $BuildChoice = Read-Host "Choice [1]"
    if (-not $BuildChoice) { $BuildChoice = "1" }
    $BuildTool = switch ($BuildChoice) {
        "1" { "maven" }
        "2" { "gradle" }
        default { Fail "Invalid choice." }
    }
}

Write-Host ""
$BasePackage = Read-Host "Base package (e.g. com.example.perf)"
if (-not $BasePackage) { $BasePackage = "perf" }

$SimClass = Read-Host "Simulation class name (e.g. ApiSimulation)"
if (-not $SimClass) { $SimClass = "ApiSimulation" }

$BaseUrl = Read-Host "Target base URL (e.g. https://api.example.com)"
if (-not $BaseUrl) { $BaseUrl = "https://api.example.com" }

# ── Create project structure ──────────────────────────────────────────────────
$TargetDir = ".\$ProjectName"
Write-Info "Creating project at $TargetDir\"

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

if ($Lang -notin @("typescript","javascript")) {
    $PackagePath = $BasePackage.Replace(".", "\")
    $SrcExt = if ($Lang -eq "scala") { "scala" } elseif ($Lang -eq "kotlin") { "kotlin" } else { "java" }
    $FileExt = if ($Lang -eq "kotlin") { "kt" } elseif ($Lang -eq "scala") { "scala" } else { "java" }

    $SimDir = "$TargetDir\src\test\$SrcExt\$PackagePath"
    $ResDir = "$TargetDir\src\test\resources"
    New-Item -ItemType Directory -Force -Path $SimDir | Out-Null
    New-Item -ItemType Directory -Force -Path "$ResDir\data" | Out-Null

    # ── pom.xml ───────────────────────────────────────────────────────────────
    if ($BuildTool -eq "maven") {
        Write-Info "Writing pom.xml..."
        $ScalaPlugin = if ($Lang -eq "scala") {
@"
    <plugin>
      <groupId>net.alchim31.maven</groupId>
      <artifactId>scala-maven-plugin</artifactId>
      <version>4.9.2</version>
      <executions>
        <execution>
          <goals><goal>testCompile</goal></goals>
        </execution>
      </executions>
    </plugin>
"@
        } else { "" }

        $KotlinPlugin = if ($Lang -eq "kotlin") {
@"
    <plugin>
      <groupId>org.jetbrains.kotlin</groupId>
      <artifactId>kotlin-maven-plugin</artifactId>
      <version>2.0.0</version>
      <executions>
        <execution>
          <id>test-compile</id>
          <goals><goal>test-compile</goal></goals>
        </execution>
      </executions>
    </plugin>
"@
        } else { "" }

        @"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
           http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$BasePackage</groupId>
  <artifactId>$ProjectName</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.release>17</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <gatling.version>3.14.5</gatling.version>
    <gatling-maven-plugin.version>4.14.0</gatling-maven-plugin.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>io.gatling.highcharts</groupId>
      <artifactId>gatling-charts-highcharts</artifactId>
      <version>`${gatling.version}</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
  <build>
    <plugins>
$ScalaPlugin$KotlinPlugin
      <plugin>
        <groupId>io.gatling</groupId>
        <artifactId>gatling-maven-plugin</artifactId>
        <version>`${gatling-maven-plugin.version}</version>
      </plugin>
    </plugins>
  </build>
</project>
"@ | Set-Content "$TargetDir\pom.xml" -Encoding UTF8
    } else {
        # Gradle
        Write-Info "Writing build.gradle..."
        @"
plugins {
  id 'io.gatling.gradle' version '4.14.0'
}
group = '$BasePackage'
version = '1.0.0-SNAPSHOT'
gatling {
  jvmArgs = ['-Xms512m', '-Xmx2g']
}
dependencies {
  gatling 'io.gatling.highcharts:gatling-charts-highcharts:3.14.5'
}
"@ | Set-Content "$TargetDir\build.gradle" -Encoding UTF8
    }

    # ── Resources ─────────────────────────────────────────────────────────────
    Write-Info "Writing gatling.conf and logback-test.xml..."
    @"
gatling {
  core { encoding = "utf-8" }
  http {
    requestTimeout = 60000
    connectTimeout = 10000
  }
}
"@ | Set-Content "$ResDir\gatling.conf" -Encoding UTF8

    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%d{HH:mm:ss.SSS} [%-5level] %logger{15} - %msg%n</pattern>
    </encoder>
  </appender>
  <root level="WARN"><appender-ref ref="CONSOLE" /></root>
</configuration>
"@ | Set-Content "$ResDir\logback-test.xml" -Encoding UTF8

    "username,password`nuser01,pass01`nuser02,pass02`nuser03,pass03" |
        Set-Content "$ResDir\data\users.csv" -Encoding UTF8

    # ── Simulation ────────────────────────────────────────────────────────────
    Write-Info "Writing simulation class..."
    if ($Lang -eq "java") {
        @"
package $BasePackage;

import io.gatling.javaapi.core.*;
import io.gatling.javaapi.http.*;
import java.time.Duration;
import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

public class $SimClass extends Simulation {

  private final HttpProtocolBuilder httpProtocol = http
      .baseUrl(System.getProperty("baseUrl", "$BaseUrl"))
      .acceptHeader("application/json")
      .contentTypeHeader("application/json");

  private final FeederBuilder<String> userFeeder = csv("data/users.csv").circular();

  private final ScenarioBuilder scn = scenario("$SimClass")
      .feed(userFeeder)
      .exec(http("GET Home").get("/").check(status().is(200)))
      .pause(1, 3);
      // TODO: add your requests here

  private static final int USERS = Integer.getInteger("users", 10);

  {
    setUp(scn.injectOpen(rampUsers(USERS).during(Duration.ofSeconds(60)))
        .protocols(httpProtocol))
    .assertions(
        global().successfulRequests().percent().gt(99.0),
        global().responseTime().percentile(95).lt(1000)
    );
  }
}
"@ | Set-Content "$SimDir\$SimClass.java" -Encoding UTF8
    }
} else {
    # JS / TS
    $SimDir = "$TargetDir\src\simulations"
    $ResDir = "$TargetDir\src\resources\data"
    New-Item -ItemType Directory -Force -Path $SimDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ResDir | Out-Null

    Write-Info "Writing package.json..."
    @"
{
  "name": "$ProjectName",
  "version": "1.0.0",
  "scripts": {
    "test": "gatling run",
    "test:all": "gatling run"
  },
  "devDependencies": {
    "@gatling.io/cli": "^3.14.5",
    "@gatling.io/sdk": "^3.14.5"
  }
}
"@ | Set-Content "$TargetDir\package.json" -Encoding UTF8

    "username,password`nuser01,pass01`nuser02,pass02`nuser03,pass03" |
        Set-Content "$ResDir\users.csv" -Encoding UTF8
}

# ── .gitignore ────────────────────────────────────────────────────────────────
Write-Info "Writing .gitignore..."
@"
target/
build/
node_modules/
.idea/
*.iml
.vscode/
.DS_Store
Thumbs.db
"@ | Set-Content "$TargetDir\.gitignore" -Encoding UTF8

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Success "Project created at $TargetDir\"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. cd $ProjectName"
if ($BuildTool -eq "maven") {
    Write-Host "  2. mvn gatling:test -Dgatling.simulationClass=$BasePackage.$SimClass"
} elseif ($BuildTool -eq "gradle") {
    Write-Host "  2. gradle gatlingRun-$BasePackage.$SimClass"
} else {
    Write-Host "  2. npm install"
    Write-Host "  3. npm test"
}
Write-Host ""
