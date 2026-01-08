/* =====================================================
   Interactive Bubble + ECG Intro (p5.js / WEBGL)
   - Touch + mouse supported
   - p5.sound mic reactive ECG (requires user gesture)
   - Transparent bubble artifacts mitigated:
       draw bubbles with DEPTH_TEST disabled + z-sort far->near
   - Avatars are always front-facing (2D HUD overlay)
   ===================================================== */

// ---------------------
// Sound (Mic reactive ECG)
// ---------------------
let micIn = null;
let micAmp = null;
let enableMic = true;
let micLevelSmoothed = 0; // 0..1
let audioReady = false;   // becomes true after userStartAudio()

// ---------------------
// Globals
// ---------------------
let bubbles = [];
let avatarImages = [];
let selectedBubble = null;
let zoomProgress = 0;

let selectedRecord = null;
let musicDetailProgress = 0;

let phonePromptProgress = 0;

// Display modes
// -2: ECG (first)
// -1: Message
//  0: Bubble normal
//  1: Bubble zoom
//  2: Music detail
//  3: Phone prompt
let displayMode = -2;

// Stars
let stars = [];

// ECG data
let ecgPoints = [];
let ecgOffset = 0;
let introTimer = 0;

let ecgAmplitudeBase = 1.0;
let ecgWaveLengthBase = 520;
let ecgDrift = 0;

// Pulse circle
let pulseCircleSize = 0;
let pulsePhase = 0;

// ---------- Assets ----------
function preload() {
  // Put these files in: ./assets/avatar1.png etc.
  // If missing, the sketch still runs; avatars will be skipped.
  try {
    avatarImages[0] = loadImage("avatar1.png");
    avatarImages[1] = loadImage("avatar2.png");
    avatarImages[2] = loadImage("avatar3.png");
  } catch (e) {
    avatarImages = [];
  }
}

// =====================================================
// Music info
// =====================================================
class MusicInfo {
  constructor() {
    const titles = ["Midnight Dreams", "Summer Breeze", "Electric Soul", "Neon Lights", "Ocean Waves", "City Pulse"];
    const artists = ["The Dreamers", "Soul Collective", "Digital Hearts", "Night Riders", "Wave Makers", "Urban Sound"];
    const albums = ["Night Sessions", "Golden Hour", "Future Sounds", "Endless Journey", "Deep Blue", "Metropolitan"];

    this.title = random(titles);
    this.artist = random(artists);
    this.album = random(albums);
    this.albumColor = color(random(100, 255), random(100, 255), random(100, 255));
  }
}

// =====================================================
// Star (stable projection in 2D overlay space)
// =====================================================
class Star {
  constructor() {
    this.x = random(-width * 2, width * 2);
    this.y = random(-height * 2, height * 2);
    this.z = random(200, 2400);
    this.brightness = random(100, 255);
    this.twinkleSpeed = random(0.01, 0.03);
    this.twinklePhase = random(TWO_PI);
  }

  update() {
    this.twinklePhase += this.twinkleSpeed;
  }

  display2D() {
    // Draw in top-left 2D coordinates (not WEBGL center)
    const f = min(width, height) * 0.9;
    const sx = width / 2 + (this.x / this.z) * f;
    const sy = height / 2 + (this.y / this.z) * f;

    const size = map(this.z, 200, 2400, 2.8, 0.6);
    const a = this.brightness * (0.7 + 0.3 * sin(this.twinklePhase));

    noStroke();
    fill(255, a);
    circle(sx, sy, size);
  }
}

// =====================================================
// Music Record
// =====================================================
class MusicRecord {
  constructor() {
    const angle = random(TWO_PI);
    const distance = random(40, 80);
    this.pos = createVector(cos(angle) * distance, sin(angle) * distance);
    this.vel = p5.Vector.random2D().mult(0.3);
    this.size = random(18, 30);
    this.rotation = random(TWO_PI);
    this.recordColor = color(random(40, 80), random(40, 80), random(40, 80));
    this.info = new MusicInfo();
  }

  update() {
    this.pos.add(this.vel);
    this.rotation += 0.02;

    const maxDist = 70;
    if (this.pos.mag() > maxDist) {
      const normal = this.pos.copy().normalize();
      const dotProduct = this.vel.dot(normal);
      this.vel.sub(p5.Vector.mult(normal, 2 * dotProduct));
      this.pos = normal.mult(maxDist);
    }
  }

  display2D(alpha01) {
    push();
    translate(this.pos.x, this.pos.y);
    rotate(this.rotation);

    fill(red(this.recordColor), green(this.recordColor), blue(this.recordColor), alpha01 * 220);
    stroke(0, alpha01 * 120);
    strokeWeight(1.5);
    circle(0, 0, this.size);

    fill(100, alpha01 * 180);
    noStroke();
    circle(0, 0, this.size * 0.3);

    noFill();
    stroke(0, alpha01 * 60);
    strokeWeight(0.8);
    for (let i = 1; i < 5; i++) circle(0, 0, this.size * 0.4 + i * 2.5);

    pop();
  }
}

// =====================================================
// Bubble (soap bubble look)
// =====================================================
class Bubble {
  constructor(x, y, z_, s, interactive) {
    this.pos = createVector(x, y);
    this.z = z_;
    this.vel = p5.Vector.random2D().mult(random(0.15, 0.4));
    this.size = s;
    this.rotation = random(TWO_PI);
    this.rotSpeed = random(-0.005, 0.005);
    this.isInteractive = interactive;

    const colorType = floor(random(8));
    switch (colorType) {
      case 0: this.bubbleColor = color(random(80, 150), random(150, 220), random(200, 255)); break;
      case 1: this.bubbleColor = color(random(180, 255), random(100, 180), random(200, 255)); break;
      case 2: this.bubbleColor = color(random(220, 255), random(150, 200), random(80, 140)); break;
      case 3: this.bubbleColor = color(random(100, 180), random(200, 255), random(150, 200)); break;
      case 4: this.bubbleColor = color(random(220, 255), random(100, 150), random(140, 200)); break;
      case 5: this.bubbleColor = color(random(80, 150), random(200, 255), random(200, 255)); break;
      case 6: this.bubbleColor = color(random(150, 200), random(100, 160), random(220, 255)); break;
      case 7: this.bubbleColor = color(random(180, 230), random(220, 255), random(100, 160)); break;
    }

    this.alpha = random(0.16, 0.30);
    this.pulsePhase = random(TWO_PI);

    this.avatarImage = null;
    this.records = null;

    if (this.isInteractive) {
      if (avatarImages && avatarImages.length > 0) {
        const img = random(avatarImages);
        if (img) this.avatarImage = img;
      }
      this.records = [];
      for (let i = 0; i < 10; i++) this.records.push(new MusicRecord());
    }
  }

  update() {
    this.pos.add(this.vel);
    this.rotation += this.rotSpeed;
    this.pulsePhase += 0.02;

    if (this.isInteractive && this.records) {
      for (const r of this.records) r.update();
    }

    const boundary = width * 1.2;
    if (this.pos.x < -boundary || this.pos.x > boundary) {
      this.vel.x *= -1;
      this.pos.x = constrain(this.pos.x, -boundary, boundary);
    }
    if (this.pos.y < -height || this.pos.y > height) {
      this.vel.y *= -1;
      this.pos.y = constrain(this.pos.y, -height, height);
    }

    if (this.isInteractive) {
      for (const other of bubbles) {
        if (other !== this && other.isInteractive && abs(this.z - other.z) < 200) {
          const d = p5.Vector.dist(this.pos, other.pos);
          if (d < (this.size + other.size) / 2) {
            const pushDir = p5.Vector.sub(this.pos, other.pos).normalize();
            this.vel.add(pushDir.mult(0.1));
            this.vel.limit(0.6);
          }
        }
      }
    }
  }

  display3D() {
    push();
    translate(this.pos.x, this.pos.y, this.z);

    const depthScale = map(this.z, -1500, 500, 0.3, 1.2);
    const depthAlpha = map(this.z, -1500, 500, 0.25, 1.0);
    scale(depthScale);

    rotateY(this.rotation);
    rotateX(sin(this.pulsePhase) * 0.08);

    const pulse = 1 + sin(this.pulsePhase) * 0.04;
    const currentSize = this.size * pulse;

    this.drawSoapBubbleSphere(currentSize / 2, depthAlpha);
    pop();
  }

  // White-blowout resistant shading
  drawSoapBubbleSphere(r, depthAlpha) {
    noStroke();

    // p5 material
    specularMaterial(80);
    shininess(10);

    let a = 255 * this.alpha * depthAlpha;
    a *= 0.85;

    const c = this.bubbleColor;
    // specularMaterial sets base; we also set ambient-ish tint via fill
    // In WEBGL, fill affects some materials; keep it for alpha.
    fill(red(c), green(c), blue(c), a);

    const depthScale = map(this.z, -1500, 500, 0.3, 1.2);
    let detail = floor(map(depthScale, 0.3, 1.2, 12, 32));
    detail = constrain(detail, 10, 34);
    sphereDetail(detail);
    sphere(r);

    // 2D-ish rim (still in current 3D transform, but works as a ring)
    push();
    noFill();
    const rimA1 = 38 * depthAlpha;
    const rimA2 = 18 * depthAlpha;

    const hueT = (sin(frameCount * 0.008) * 0.5 + 0.5);
    const rimC1 = lerpColor(color(120, 220, 255), color(255, 180, 230), hueT);
    const rimC2 = lerpColor(color(150, 255, 150), color(255, 240, 150), 1 - hueT);

    stroke(rimC1);
    strokeWeight(1.6);
    stroke(red(rimC1), green(rimC1), blue(rimC1), rimA1);
    circle(0, 0, r * 2.02);

    stroke(rimC2);
    strokeWeight(2.6);
    stroke(red(rimC2), green(rimC2), blue(rimC2), rimA2);
    circle(0, 0, r * 2.07);

    pop();
  }

  displayMusicRecords2D() {
    if (!this.isInteractive || !this.records) return;

    push();
    translate(0, this.size * 0.15);
    for (const r of this.records) {
      // NOTE: Processing版はここでupdate()を二重に呼ぶ可能性があったので、p5版では呼び出し側で統一してもOK
      r.display2D(1.0);
    }
    pop();
  }

  isClickedScreen(mx, my) {
    if (!this.isInteractive) return false;
    const depthScale = map(this.z, -1500, 500, 0.3, 1.2);

    // In WEBGL, logical center is (0,0). We'll convert screen -> WEBGL center space.
    const xC = mx - width / 2;
    const yC = my - height / 2;

    const d = dist(xC, yC, this.pos.x, this.pos.y);
    return d < (this.size * depthScale) / 2;
  }
}

// =====================================================
// Setup
// =====================================================
function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  smooth();

  // mic setup is deferred until user gesture (mobile policy).
  // We'll still create objects now; actual audio starts on first tap.
  if (enableMic) {
    try {
      micIn = new p5.AudioIn();
      micAmp = new p5.Amplitude();
    } catch (e) {
      enableMic = false;
    }
  }

  generateECG(0.0);

  stars = [];
  for (let i = 0; i < 280; i++) stars.push(new Star());

  bubbles = [];

  const bubbleSize = min(width, height) / 2.5;

  for (let i = 0; i < 10; i++) {
    const angle = random(TWO_PI);
    const distance = random(width * 0.2, width * 0.6);
    const x = cos(angle) * distance;
    const y = sin(angle) * distance;
    const z = random(-300, 300);
    bubbles.push(new Bubble(x, y, z, bubbleSize, true));
  }

  for (let i = 0; i < 10; i++) {
    const angle = random(TWO_PI);
    const distance = random(width * 0.5, width * 1.5);
    const x = cos(angle) * distance;
    const y = sin(angle) * distance;
    const z = random(-1500, -600);
    bubbles.push(new Bubble(x, y, z, bubbleSize * random(0.8, 1.5), false));
  }
}

// =====================================================
// ECG generation
// =====================================================
function generateECG(micLevel01) {
  ecgPoints = [];

  const amp = ecgAmplitudeBase * lerp(0.9, 1.45, micLevel01);
  const noiseAmt = lerp(0.6, 2.2, micLevel01);
  const waveLength = ecgWaveLengthBase * lerp(1.05, 0.85, micLevel01);

  for (let i = 0; i < width * 2; i += 3) {
    let y = height / 2 + 120;

    const drift = sin((i * 0.002) + ecgDrift) * 4.0;
    y += drift;

    y += random(-2.0, 2.0) * amp * noiseAmt;

    const spikePos = (i % waveLength);
    const spikeProgress = spikePos / waveLength;

    if (spikeProgress < 0.06) {
      y -= sin((spikeProgress / 0.06) * PI) * 10 * amp;
    } else if (spikeProgress > 0.17 && spikeProgress < 0.28) {
      const qrsProgress = (spikeProgress - 0.17) / 0.11;
      if (qrsProgress < 0.28) {
        y += sin((qrsProgress / 0.28) * PI) * 22 * amp;
      } else if (qrsProgress < 0.52) {
        y -= sin(((qrsProgress - 0.28) / 0.24) * PI) * 150 * amp;
      } else {
        y += sin(((qrsProgress - 0.52) / 0.48) * PI) * 40 * amp;
      }
    } else if (spikeProgress > 0.43 && spikeProgress < 0.54) {
      y -= sin(((spikeProgress - 0.43) / 0.11) * PI) * 18 * amp;
    }

    ecgPoints.push(createVector(i, y));
  }
}

// =====================================================
// Lighting for bubbles (once per frame)
// =====================================================
function setupBubbleLights() {
  // In WEBGL, calling lights() resets light settings; we explicitly set softer lights.
  ambientLight(18, 18, 24);
  directionalLight(55, 55, 65, -0.2, -0.6, -1);
  directionalLight(28, 32, 45, 0.8, 0.2, -1);
}

// =====================================================
// 2D overlay helpers (draw in screen space)
// =====================================================
function begin2DOverlay() {
  push();
  // reset to screen top-left
  resetMatrix();
  translate(-width / 2, -height / 2, 0);
}

function end2DOverlay() {
  pop();
}

// Avatars overlay (normal)
function drawAvatarsOverlayNormal() {
  begin2DOverlay();

  // disable depth for HUD
  drawingContext.disable(drawingContext.DEPTH_TEST);

  imageMode(CENTER);
  for (const b of bubbles) {
    if (!b.isInteractive || !b.avatarImage) continue;

    const depthScale = map(b.z, -1500, 500, 0.3, 1.2);
    const depthAlpha = map(b.z, -1500, 500, 0.25, 1.0);

    const screenX = width / 2 + b.pos.x;
    const screenY = height / 2 + b.pos.y;
    const avatarSize = (b.size * 0.36) * depthScale;

    tint(255, 180 * depthAlpha);
    image(b.avatarImage, screenX, screenY, avatarSize, avatarSize);
  }
  noTint();

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// Zoom mode avatar overlay
function drawAvatarOverlayZoom(t) {
  if (!selectedBubble || !selectedBubble.isInteractive || !selectedBubble.avatarImage) return;

  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);

  const a = 220 * t;
  const avatarSize = (selectedBubble.size * 0.42) * lerp(1, 1.20, t);

  imageMode(CENTER);
  tint(255, a);
  image(selectedBubble.avatarImage, width / 2, height / 4, avatarSize, avatarSize);
  noTint();

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// =====================================================
// Main draw
// =====================================================
function draw() {
  background(5, 10, 20);

  // Mic smoothing
  let micNow = 0;
  if (enableMic && audioReady && micAmp) {
    micNow = constrain(micAmp.getLevel() * 7.0, 0, 1);
  }
  micLevelSmoothed = lerp(micLevelSmoothed, micNow, 0.08);

  if (displayMode === -2) {
    drawECGScreen(micLevelSmoothed);
    return;
  }

  if (displayMode === -1) {
    drawMessageScreen();
    return;
  }

  if (displayMode === 3) {
    if (phonePromptProgress < 1) phonePromptProgress += 0.03;
    drawPhonePrompt();
    return;
  }

  if (displayMode === 2) {
    if (musicDetailProgress < 1) musicDetailProgress += 0.05;
    if (phonePromptProgress > 0) phonePromptProgress -= 0.1;
    drawMusicDetail();
    return;
  }

  if (displayMode === 1) {
    if (zoomProgress < 1) zoomProgress += 0.05;
    if (musicDetailProgress > 0) musicDetailProgress -= 0.1;
    if (phonePromptProgress > 0) phonePromptProgress -= 0.1;
    drawZoomedBubble();
    return;
  }

  // displayMode === 0
  if (zoomProgress > 0) zoomProgress -= 0.05;
  if (musicDetailProgress > 0) musicDetailProgress -= 0.1;
  if (phonePromptProgress > 0) phonePromptProgress -= 0.1;

  // Stars in 2D overlay
  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);
  for (const s of stars) { s.update(); s.display2D(); }
  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();

  // Bubble scene in WEBGL center coordinates
  // sort far -> near by z
  bubbles.sort((a, b) => a.z - b.z);

  // transparent spheres: draw with depth test off, in sorted order
  drawingContext.disable(drawingContext.DEPTH_TEST);
  setupBubbleLights();

  for (const b of bubbles) {
    b.update();
    b.display3D();
  }

  drawingContext.enable(drawingContext.DEPTH_TEST);

  // Avatars HUD overlay
  drawAvatarsOverlayNormal();
}

// =====================================================
// ECG Screen
// =====================================================
function drawECGScreen(micLevel01) {
  // ECG is drawn as 2D overlay
  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);

  background(10, 15, 25);

  ecgOffset -= 2.0;
  if (ecgOffset < -width) ecgOffset = 0;

  ecgDrift += 0.015;

  const regenInterval = floor(lerp(16, 8, micLevel01));
  if (frameCount % regenInterval === 0) {
    generateECG(micLevel01);
  }

  const drawWave = (a, w) => {
    stroke(255, a);
    strokeWeight(w);
    noFill();
    beginShape();
    for (let i = 0; i < ecgPoints.length - 1; i++) {
      const p = ecgPoints[i];
      const x = p.x + ecgOffset;
      const y = p.y;
      if (x > -50 && x < width + 50) vertex(x, y);
    }
    endShape();
  };

  drawWave(40, 10);
  drawWave(70, 6);
  drawWave(220, 3);

  pulsePhase += 0.05;
  const audioBoost = lerp(1.0, 1.6, micLevel01);
  pulseCircleSize = (100 + 50 * sin(pulsePhase)) * audioBoost;
  const circleAlpha = (150 + 105 * sin(pulsePhase)) * lerp(0.9, 1.3, micLevel01);

  push();
  translate(width / 2, height / 2 + 100);

  for (let i = 3; i > 0; i--) {
    noFill();
    stroke(255, circleAlpha / (i + 1));
    strokeWeight(i * 3);
    circle(0, 0, pulseCircleSize + i * 30);
  }

  noFill();
  stroke(255, circleAlpha);
  strokeWeight(4);
  circle(0, 0, pulseCircleSize);

  pop();

  fill(255, 230);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(32);
  text("Hold your smartphone on the screen.", width / 2, height / 2 + 250);

  textSize(18);
  fill(255, 180);
  text("Tap the screen to continue", width / 2, height - 50);

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// =====================================================
// Message Screen
// =====================================================
function drawMessageScreen() {
  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);

  background(5, 10, 20);

  introTimer += deltaTime / 1000;
  const textAlpha = min(255, introTimer * 100);

  fill(255, textAlpha);
  noStroke();
  textAlign(CENTER, CENTER);

  textSize(28);
  text("Let's discover songs you don't know from others' perspectives.", width / 2, height / 2);

  textSize(18);
  fill(255, textAlpha * 0.75);
  text("Tap to skip", width / 2, height - 50);

  if (introTimer > 3) {
    displayMode = 0;
    introTimer = 0;
  }

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// =====================================================
// Zoomed Bubble
// =====================================================
function drawZoomedBubble() {
  const t = easeInOutCubic(zoomProgress);

  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);
  fill(5, 10, 20, 200 * t);
  noStroke();
  rect(0, 0, width, height);
  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();

  push(); // WEBGL
  const bubbleScale = lerp(1, 1.8, t);
  scale(bubbleScale);

  if (selectedBubble) {
    drawingContext.disable(drawingContext.DEPTH_TEST);
    setupBubbleLights();
    // draw centered bubble (origin is center in WEBGL)
    selectedBubble.drawSoapBubbleSphere(selectedBubble.size * 0.5, 1.0);
    drawingContext.enable(drawingContext.DEPTH_TEST);
  }

  // draw records after bubble is large enough (in 2D within WEBGL)
  if (t > 0.8 && selectedBubble && selectedBubble.records) {
    drawingContext.disable(drawingContext.DEPTH_TEST);
    begin2DOverlay();
    drawingContext.disable(drawingContext.DEPTH_TEST);

    // Place records around center; mimic Processing layout
    translate(width / 2, height / 2);
    scale(bubbleScale);

    // update+draw
    push();
    translate(0, selectedBubble.size * 0.15);
    for (const r of selectedBubble.records) {
      r.update();
      r.display2D(1.0);
    }
    pop();

    drawingContext.enable(drawingContext.DEPTH_TEST);
    end2DOverlay();
    drawingContext.enable(drawingContext.DEPTH_TEST);
  }

  pop();

  if (t > 0.05) drawAvatarOverlayZoom(t);

  if (t > 0.9) {
    begin2DOverlay();
    drawingContext.disable(drawingContext.DEPTH_TEST);
    fill(255, 200);
    noStroke();
    textAlign(CENTER, CENTER);
    textSize(20);
    text("Tap the record to play the song", width / 2, height - 80);
    drawingContext.enable(drawingContext.DEPTH_TEST);
    end2DOverlay();
  }
}

// =====================================================
// Music Detail Screen
// =====================================================
function drawMusicDetail() {
  const t = easeInOutCubic(musicDetailProgress);

  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);
  fill(5, 10, 20, 240 * t);
  noStroke();
  rect(0, 0, width, height);
  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();

  // Record animation in 2D overlay
  if (selectedRecord) {
    begin2DOverlay();
    drawingContext.disable(drawingContext.DEPTH_TEST);

    push();
    translate(width / 2, height / 2 - 50);

    const recordScale = lerp(1, 12, t);
    scale(recordScale);
    rotate(selectedRecord.rotation + frameCount * 0.01);

    fill(selectedRecord.recordColor);
    stroke(0, 150);
    strokeWeight(2 / recordScale);
    circle(0, 0, selectedRecord.size);

    fill(100);
    noStroke();
    circle(0, 0, selectedRecord.size * 0.3);

    noFill();
    stroke(0, 100);
    strokeWeight(1 / recordScale);
    for (let i = 1; i < 8; i++) circle(0, 0, selectedRecord.size * 0.4 + i * 3);

    fill(255, 60);
    noStroke();
    arc(0, 0, selectedRecord.size * 0.8, selectedRecord.size * 0.8, -PI / 3, PI / 3);

    pop();

    drawingContext.enable(drawingContext.DEPTH_TEST);
    end2DOverlay();
  }

  if (t > 0.5) drawMusicPlayer(t);

  if (t > 0.7) {
    begin2DOverlay();
    drawingContext.disable(drawingContext.DEPTH_TEST);
    fill(255, 200 * (t - 0.7) / 0.3);
    noStroke();
    textAlign(CENTER, CENTER);
    textSize(18);
    text("if you like it,lets tap the record", width / 2, height - 60);
    drawingContext.enable(drawingContext.DEPTH_TEST);
    end2DOverlay();
  }
}

// =====================================================
// Music Player panel
// =====================================================
function drawMusicPlayer(t) {
  const alpha = map(t, 0.5, 1, 0, 255);

  const panelW = width * 0.62;
  const panelH = 210;
  const radius = 18;

  const cx = width / 2;
  const cy = height * 0.78;

  const info = selectedRecord ? selectedRecord.info : null;

  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);

  push();
  translate(cx, cy);

  fill(20, 25, 35, alpha);
  noStroke();
  rectMode(CENTER);
  rect(0, 0, panelW, panelH, radius);

  const topY = -60;
  const titleY = topY;
  const artistY = topY + 28;
  const albumY = topY + 52;

  fill(255, alpha);
  textAlign(CENTER, CENTER);

  textSize(24);
  text(info ? info.title : "—", 0, titleY);

  textSize(18);
  fill(210, alpha);
  text(info ? info.artist : "", 0, artistY);

  textSize(15);
  fill(170, alpha);
  text(info ? info.album : "", 0, albumY);

  const btnY = 62;
  const btnR = 64;

  fill(255, alpha);
  noStroke();
  circle(0, btnY, btnR);

  fill(20, 25, 35, alpha);
  triangle(-10, btnY - 12, -10, btnY + 12, 16, btnY);

  pop();

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// =====================================================
// Phone Prompt
// =====================================================
function drawPhonePrompt() {
  const t = easeInOutCubic(phonePromptProgress);

  begin2DOverlay();
  drawingContext.disable(drawingContext.DEPTH_TEST);

  fill(5, 10, 20, 250);
  noStroke();
  rect(0, 0, width, height);

  push();
  translate(width / 2, height / 2);

  fill(255, 255 * t);
  textAlign(CENTER, CENTER);
  textSize(32);
  text("Hold your smartphone on the screen.", 0, -200);

  const blinkAlpha = 150 + 105 * sin(frameCount * 0.05);

  fill(255, blinkAlpha * t);
  noStroke();
  rectMode(CENTER);
  rect(0, 50, 180, 320, 20);

  fill(200, 220, 255, blinkAlpha * 0.6 * t);
  rect(0, 40, 160, 280, 10);

  fill(255, blinkAlpha * t);
  circle(0, 190, 40);

  fill(50, blinkAlpha * t);
  circle(0, -140, 12);

  for (let i = 1; i <= 3; i++) {
    noFill();
    stroke(255, blinkAlpha * 0.3 * t / i);
    strokeWeight(i * 4);
    rect(0, 50, 180 + i * 20, 320 + i * 20, 20 + i * 5);
  }

  pop();

  fill(255, 150 * t);
  textAlign(CENTER, CENTER);
  textSize(16);
  text("Tap the black area to return to the previous screen.", width / 2, height - 40);

  drawingContext.enable(drawingContext.DEPTH_TEST);
  end2DOverlay();
}

// =====================================================
// Easing
// =====================================================
function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
}

// =====================================================
// Unified pointer interaction (mouse + touch)
// =====================================================
function ensureAudioStarted() {
  // Mobile browsers require user gesture for audio
  if (!enableMic || audioReady) return;

  try {
    userStartAudio().then(() => {
      audioReady = true;
      micIn.start(() => {
        // route mic into amplitude analyzer
        micAmp.setInput(micIn);
      });
    }).catch(() => {
      // user denied; keep running without mic
      audioReady = false;
      enableMic = false;
    });
  } catch (e) {
    audioReady = false;
    enableMic = false;
  }
}

function pointerPressed(mx, my) {
  ensureAudioStarted();

  if (displayMode === -2) {
    displayMode = -1;
    introTimer = 0;
    return;
  }

  if (displayMode === -1) {
    displayMode = 0;
    introTimer = 0;
    return;
  }

  if (displayMode === 3) {
    displayMode = 2;
    phonePromptProgress = 0;
    return;
  }

  if (displayMode === 2) {
    // Processing logic used distance from (width/2, height/2 - 50)
    const distFromCenter = dist(mx, my, width / 2, height / 2 - 50);
    if (distFromCenter < 100) {
      displayMode = 3;
      phonePromptProgress = 0;
    } else if (distFromCenter > 200) {
      displayMode = 1;
      selectedRecord = null;
      musicDetailProgress = 0;
    }
    return;
  }

  if (displayMode === 1) {
    let recordClicked = false;

    if (selectedBubble && zoomProgress > 0.8 && selectedBubble.records) {
      const bubbleScale = lerp(1, 1.8, easeInOutCubic(zoomProgress));

      // Records are drawn around WEBGL center, so their “screen” position is:
      // screenX = width/2 + r.pos.x * bubbleScale
      // screenY = height/2 + r.pos.y * bubbleScale + selectedBubble.size * 0.15 * bubbleScale
      for (const r of selectedBubble.records) {
        const screenX = width / 2 + r.pos.x * bubbleScale;
        const screenY = height / 2 + r.pos.y * bubbleScale + selectedBubble.size * 0.15 * bubbleScale;
        const d = dist(mx, my, screenX, screenY);

        if (d < (r.size * bubbleScale) / 2) {
          selectedRecord = r;
          displayMode = 2;
          musicDetailProgress = 0;
          recordClicked = true;
          break;
        }
      }
    }

    if (!recordClicked) {
      const distFromCenter = dist(mx, my, width / 2, height / 2);
      if (distFromCenter > 400) {
        displayMode = 0;
        selectedBubble = null;
        selectedRecord = null;
        zoomProgress = 0;
      }
    }
    return;
  }

  if (displayMode === 0) {
    for (const b of bubbles) {
      if (b.isClickedScreen(mx, my)) {
        selectedBubble = b;
        displayMode = 1;
        zoomProgress = 0;
        break;
      }
    }
  }
}

// Mouse
function mousePressed() {
  pointerPressed(mouseX, mouseY);
  return false;
}

// Touch
function touchStarted() {
  // Use first touch point
  if (touches && touches.length > 0) {
    pointerPressed(touches[0].x, touches[0].y);
  } else {
    pointerPressed(mouseX, mouseY);
  }
  return false; // prevent scrolling
}

// =====================================================
// Resize
// =====================================================
function windowResized() {
  resizeCanvas(windowWidth, windowHeight);

  // Rebuild ECG to match new width
  generateECG(micLevelSmoothed);

  // Optional: you can also re-seed stars for new screen sizes
  stars = [];
  for (let i = 0; i < 280; i++) stars.push(new Star());
}
