import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scene",
    "profileChart",
    "groundChart",
    "performanceChart",
    "dynamicsChart",
    "environmentChart",
    "powerChart",
    "scrubber",
    "timeLabel",
    "playButton",
    "video",
    "videoExitOffsetInput",
    "videoExitOffsetLabel"
  ]

  static values = {
    points: Array,
    sensors: Array,
    bounds: Object,
    cesiumToken: String,
    labels: Object,
    videoExitOffset: Number
  }

  async connect() {
    this.points = this.pointsValue.filter((point) =>
      Number.isFinite(Number(point.lat)) &&
      Number.isFinite(Number(point.lon)) &&
      Number.isFinite(Number(point.alt))
    )
    this.groundAltitude = this.groundAltitudeFromPoints()
    this.points = this.points.map((point) => ({ ...point, height: this.heightFromGround(point) }))
    this.sensors = this.sensorsValue.filter((sample) => Number.isFinite(Number(sample.t)))
    this.charts = []
    this.renderFrame = null
    this.boundSceneHandlers = []
    this.cesiumInteractionHandler = null
    this.cesiumOrbit = null
    this.cesiumOrbitHome = null
    this.cesiumDrag = null
    this.cesiumVisualPoints = null
    this.flightDuration = this.durationFromPoints()
    this.currentElapsed = 0
    this.isPlaying = false
    this.playbackFrame = null
    this.playbackStartedAt = 0
    this.playbackStartElapsed = 0
    this.playbackLastRenderAt = 0
    this.playbackLastCameraAt = 0
    this.videoExitOffset = this.hasVideoExitOffsetValue ? this.videoExitOffsetValue : null
    this.videoSyncFrame = null
    this.videoSyncLastRenderAt = 0
    this.syncingVideo = false
    this.colors = this.designColors()

    const chartModule = await import("https://cdn.jsdelivr.net/npm/chart.js@4.4.9/+esm")

    this.Chart = chartModule.Chart
    this.Chart.register(...chartModule.registerables, SILLAGE_BOUNDS_PLUGIN, SILLAGE_PLAYBACK_PLUGIN)

    this.setupCharts()
    this.updatePlayButton()
    this.updateVideoExitLabel()
    if (this.hasSceneTarget && this.points.length >= 2) this.setupScene()
    this.updateScrubbedElapsed(this.defaultElapsed())
  }

  disconnect() {
    if (this.renderFrame) cancelAnimationFrame(this.renderFrame)
    if (this.playbackFrame) cancelAnimationFrame(this.playbackFrame)
    if (this.videoSyncFrame) cancelAnimationFrame(this.videoSyncFrame)
    if (this.resizeObserver) this.resizeObserver.disconnect()
    this.boundSceneHandlers.forEach(([eventName, handler, target, options]) => target?.removeEventListener(eventName, handler, options))
    if (this.cesiumInteractionHandler && !this.cesiumInteractionHandler.isDestroyed()) this.cesiumInteractionHandler.destroy()
    this.charts.forEach((chart) => chart.destroy())
    if (this.cesiumViewer) this.cesiumViewer.destroy()
    this.disposeScene()
  }

  scrub(event) {
    this.pausePlayback()
    this.updateScrubbedElapsed((Number(event.target.value) / 1000) * this.flightDuration)
  }

  togglePlayback() {
    if (this.isPlaying) {
      this.pausePlayback()
      return
    }

    if (this.videoCanSync()) {
      this.playSyncedVideo()
      return
    }

    if (this.currentElapsed >= this.flightDuration) this.updateScrubbedElapsed(this.defaultElapsed())
    this.isPlaying = true
    this.playbackStartedAt = performance.now()
    this.playbackStartElapsed = this.currentElapsed
    this.playbackLastRenderAt = 0
    this.playbackLastCameraAt = 0
    this.updatePlayButton()
    this.playbackFrame = requestAnimationFrame((timestamp) => this.stepPlayback(timestamp))
  }

  pausePlayback(options = {}) {
    if (this.playbackFrame) cancelAnimationFrame(this.playbackFrame)
    if (this.videoSyncFrame) cancelAnimationFrame(this.videoSyncFrame)

    this.playbackFrame = null
    this.videoSyncFrame = null
    if (!options.skipVideoPause) this.pauseVideo()
    this.isPlaying = false
    this.updatePlayButton()
  }

  stepPlayback(timestamp) {
    if (!this.isPlaying) return

    const elapsed = this.playbackStartElapsed + ((timestamp - this.playbackStartedAt) / 1000)
    if (elapsed >= this.flightDuration) {
      this.updateScrubbedElapsed(this.flightDuration)
      this.pausePlayback()
      return
    }

    if (timestamp - this.playbackLastRenderAt > 80) {
      this.playbackLastRenderAt = timestamp
      const followCamera = timestamp - this.playbackLastCameraAt > 360
      if (followCamera) this.playbackLastCameraAt = timestamp
      this.updateScrubbedElapsed(elapsed, { followCamera })
    }
    this.playbackFrame = requestAnimationFrame((nextTimestamp) => this.stepPlayback(nextTimestamp))
  }

  playSyncedVideo() {
    if (!this.videoCanSync()) return

    if (this.currentElapsed >= this.flightDuration) this.updateScrubbedElapsed(this.defaultElapsed())
    this.syncVideoFromFlight()
    this.isPlaying = true
    this.videoSyncLastRenderAt = 0
    this.updatePlayButton()

    const playPromise = this.videoTarget.play()
    if (playPromise?.catch) {
      playPromise.catch(() => {
        this.isPlaying = false
        this.updatePlayButton()
      })
    }
    this.startVideoSyncLoop()
  }

  pauseVideo() {
    if (!this.hasVideoTarget || this.videoTarget.paused) return

    this.syncingVideo = true
    this.videoTarget.pause()
    this.syncingVideo = false
  }

  videoPlaybackStarted() {
    if (!this.videoCanSync() || this.syncingVideo) return

    if (this.playbackFrame) cancelAnimationFrame(this.playbackFrame)
    this.playbackFrame = null
    this.isPlaying = true
    this.videoSyncLastRenderAt = 0
    this.updatePlayButton()
    this.startVideoSyncLoop()
  }

  videoPlaybackPaused() {
    if (this.syncingVideo) return

    this.pausePlayback({ skipVideoPause: true })
  }

  videoSeeked() {
    if (!this.videoCanSync()) return

    this.updateScrubbedElapsed(this.elapsedForVideoTime(this.videoTarget.currentTime), {
      followCamera: false,
      syncVideo: false
    })
  }

  videoTimeUpdated() {
    if (!this.videoCanSync() || !this.videoTarget.paused) return

    this.videoSeeked()
  }

  startVideoSyncLoop() {
    if (this.videoSyncFrame || !this.videoCanSync()) return

    this.videoSyncFrame = requestAnimationFrame((timestamp) => this.stepVideoPlayback(timestamp))
  }

  stepVideoPlayback(timestamp) {
    this.videoSyncFrame = null
    if (!this.isPlaying || !this.videoCanSync()) return

    if (this.videoTarget.paused || this.videoTarget.ended) {
      this.pausePlayback({ skipVideoPause: true })
      return
    }

    if (timestamp - this.videoSyncLastRenderAt > 80) {
      this.videoSyncLastRenderAt = timestamp
      this.updateScrubbedElapsed(this.elapsedForVideoTime(this.videoTarget.currentTime), {
        followCamera: true,
        syncVideo: false
      })
    }

    this.startVideoSyncLoop()
  }

  updatePlayButton() {
    if (!this.hasPlayButtonTarget) return

    const label = this.label(this.isPlaying ? "pause" : "play")
    this.playButtonTarget.classList.toggle("is-playing", this.isPlaying)
    this.playButtonTarget.setAttribute("aria-label", label)
    this.playButtonTarget.title = label
  }

  resetCamera() {
    if (this.cesiumViewer && window.Cesium) {
      this.cesiumOrbit = { ...this.cesiumOrbitHome }
      this.applyCesiumOrbit(window.Cesium, this.cesiumViewer)
      return
    }

    if (!this.camera || !this.group || !this.localCameraHome) return

    this.group.rotation.set(0, 0, 0)
    this.camera.position.set(this.localCameraHome.x, this.localCameraHome.y, this.localCameraHome.z)
    this.camera.lookAt(0, 0, 0)
    this.scheduleRender()
  }

  markVideoExit(event) {
    event.preventDefault()
    if (!this.hasVideoTarget || !this.hasVideoExitOffsetInputTarget) return

    this.videoExitOffset = this.clamp(
      this.videoTarget.currentTime || 0,
      0,
      this.number(this.videoTarget.duration) || Number.MAX_SAFE_INTEGER
    )
    this.videoExitOffsetInputTarget.value = this.videoExitOffset.toFixed(3)
    this.updateVideoExitLabel()
    event.currentTarget.closest("form")?.requestSubmit()
  }

  syncVideoFromFlight() {
    this.updateVideoExitLabel()
    if (!this.videoCanSync()) return

    this.syncVideoToElapsed(this.currentElapsed)
  }

  syncVideoToElapsed(elapsed) {
    if (!this.videoCanSync()) return
    if (this.videoTarget.readyState === 0) return

    const targetTime = this.videoTimeForElapsed(elapsed)
    if (!Number.isFinite(targetTime)) return
    if (Math.abs(this.videoTarget.currentTime - targetTime) < 0.12) return

    this.syncingVideo = true
    this.videoTarget.currentTime = targetTime
    this.syncingVideo = false
  }

  videoCanSync() {
    return this.hasVideoTarget &&
      Number.isFinite(this.videoExitOffset) &&
      this.videoExitOffset >= 0
  }

  videoTimeForElapsed(elapsed) {
    const elapsedSeconds = this.number(elapsed)
    if (!Number.isFinite(elapsedSeconds) || !this.videoCanSync()) return null

    const targetTime = elapsedSeconds - this.exitElapsed() + this.videoExitOffset
    const duration = this.number(this.videoTarget.duration)
    return this.clamp(targetTime, 0, Number.isFinite(duration) ? duration : Math.max(targetTime, 0))
  }

  elapsedForVideoTime(currentTime) {
    const videoTime = this.number(currentTime)
    if (!Number.isFinite(videoTime) || !this.videoCanSync()) return this.currentElapsed

    return videoTime - this.videoExitOffset + this.exitElapsed()
  }

  updateVideoExitLabel() {
    if (!this.hasVideoExitOffsetLabelTarget) return

    this.videoExitOffsetLabelTarget.textContent = this.videoCanSync()
      ? this.label("video_exit_marked").replace("%{timestamp}", this.formatSeconds(this.videoExitOffset))
      : this.label("video_exit_unmarked")
  }

  setupCharts() {
    if (this.points.length >= 2) {
      this.setupProfileChart()
      this.setupGroundChart()
      this.setupPerformanceChart()
    }

    this.setupDynamicsChart()
    this.setupEnvironmentChart()
    this.setupPowerChart()
  }

  setupProfileChart() {
    this.createTimeChart(this.profileChartTarget, [
      this.dataset(this.label("height"), this.points, "height", this.colors.violet, "altitude"),
      this.dataset(this.label("horizontal_speed"), this.points, "hspeed", this.colors.teal, "speed"),
      this.dataset(this.label("vertical_speed"), this.points, "vspeed", this.colors.amber, "speed")
    ], {
      altitude: this.axis("left", this.label("meters")),
      speed: this.axis("right", this.label("meters_per_second"), false)
    })
  }

  setupGroundChart() {
    const data = this.points.map((point) => ({ x: this.number(point.lon), y: this.number(point.lat), t: this.number(point.t) }))
      .filter((point) => Number.isFinite(point.x) && Number.isFinite(point.y))

    this.createChart(this.groundChartTarget, {
      type: "line",
      data: {
        datasets: [{
          label: this.label("ground_track"),
          data,
          borderColor: this.colors.aqua,
          backgroundColor: this.colors.coral,
          borderWidth: 2,
          pointRadius: 1.5,
          pointHoverRadius: 3,
          tension: 0.1
        }]
      },
      options: this.chartOptions({
        x: this.axis("bottom", this.label("longitude")),
        y: this.axis("left", this.label("latitude"))
      }, false, "track")
    })
  }

  setupPerformanceChart() {
    this.createTimeChart(this.performanceChartTarget, [
      this.dataset(this.label("distance"), this.points, "distance", this.colors.lime, "distance"),
      this.dataset(this.label("glide"), this.points, "glide", this.colors.coral, "glide")
    ], {
      distance: this.axis("left", this.label("meters")),
      glide: this.axis("right", this.label("ratio"), false)
    })
  }

  setupDynamicsChart() {
    if (!this.hasDynamicsChartTarget) return

    const imu = this.sensorRows("IMU")
    this.createTimeChart(this.dynamicsChartTarget, [
      this.sensorDataset("ax", imu, this.label("acceleration_x"), this.colors.coral, "acceleration"),
      this.sensorDataset("ay", imu, this.label("acceleration_y"), this.colors.amber, "acceleration"),
      this.sensorDataset("az", imu, this.label("acceleration_z"), this.colors.lime, "acceleration"),
      this.sensorDataset("wx", imu, this.label("rotation_x"), this.colors.teal, "rotation"),
      this.sensorDataset("wy", imu, this.label("rotation_y"), this.colors.aqua, "rotation"),
      this.sensorDataset("wz", imu, this.label("rotation_z"), this.colors.violet, "rotation")
    ], {
      acceleration: this.axis("left", this.label("g")),
      rotation: this.axis("right", this.label("degrees_per_second"), false)
    })
  }

  setupEnvironmentChart() {
    if (!this.hasEnvironmentChartTarget) return

    const baro = this.sensorRows("BARO")
    this.createTimeChart(this.environmentChartTarget, [
      this.sensorDataset("pressure", baro, this.label("pressure"), this.colors.violet, "pressure"),
      this.sensorDataset("temperature", baro, this.label("temperature"), this.colors.amber, "temperature")
    ], {
      pressure: this.axis("left", this.label("pascal")),
      temperature: this.axis("right", this.label("celsius"), false)
    })
  }

  setupPowerChart() {
    if (!this.hasPowerChartTarget) return

    const power = this.sensorRows("VBAT")
    this.createTimeChart(this.powerChartTarget, [
      this.sensorDataset("voltage", power, this.label("voltage"), this.colors.coral, "voltage")
    ], {
      voltage: this.axis("left", this.label("volt"))
    })
  }

  async setupScene() {
    if (this.cesiumTokenValue) {
      await this.setupCesiumScene()
      this.updateScrubbedElapsed(this.currentElapsed, { followCamera: false })
      return
    }

    this.showSceneFallbackMessage(this.label("cesium_token_missing"))
    await this.setupLocalScene()
    this.updateScrubbedElapsed(this.currentElapsed, { followCamera: false })
  }

  async setupCesiumScene() {
    try {
      const Cesium = await this.loadCesium()
      Cesium.Ion.defaultAccessToken = this.cesiumTokenValue

      const viewer = new Cesium.Viewer(this.sceneTarget, {
        animation: false,
        baseLayerPicker: false,
        fullscreenButton: false,
        geocoder: false,
        globe: false,
        homeButton: false,
        infoBox: false,
        navigationHelpButton: false,
        sceneModePicker: false,
        selectionIndicator: false,
        timeline: false,
        requestRenderMode: true,
        maximumRenderTimeChange: Number.POSITIVE_INFINITY,
        scene3DOnly: true
      })

      this.cesiumViewer = viewer
      this.sceneCanvas = viewer.scene.canvas
      viewer.scene.debugShowFramesPerSecond = false
      this.configureCesiumDaylight(Cesium, viewer)
      this.configureCesiumCameraController(viewer)

      const tileset = await Cesium.createGooglePhotorealistic3DTileset()
      tileset.enableCollision = true
      viewer.scene.primitives.add(tileset)
      this.cesiumVisualPoints = await this.pointsLiftedAboveCesiumSurface(Cesium, viewer, tileset)
      this.addCesiumTrajectory(Cesium, viewer)
      this.setupCesiumMouseControls(Cesium, viewer)
      this.flyCesiumCamera(Cesium, viewer)
      viewer.scene.requestRender()
    } catch (error) {
      console.warn(`Cesium unavailable, using local 3D fallback: ${error.message || error}`)
      this.sceneTarget.replaceChildren()
      this.showSceneFallbackMessage(this.label("cesium_unavailable"))
      await this.setupLocalScene()
    }
  }

  async setupLocalScene() {
    const THREE = await import("https://cdn.jsdelivr.net/npm/three@0.164.1/build/three.module.js")
    const canvas = document.createElement("canvas")
    canvas.className = "trajectory-canvas"
    this.sceneTarget.appendChild(canvas)
    this.sceneCanvas = canvas

    const context = this.webglContext(canvas)
    if (!context) {
      this.showSceneFallback(canvas)
      return
    }

    const coordinates = this.localCoordinates()
    const bounds = this.coordinateBounds(coordinates)
    const span = Math.max(bounds.x, bounds.y, bounds.z, 40)

    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(this.colors.daySky)

    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, span * 12)
    this.camera.position.set(span * 0.9, span * 0.65, span * 1.4)
    this.camera.lookAt(0, 0, 0)
    this.localCameraHome = {
      x: this.camera.position.x,
      y: this.camera.position.y,
      z: this.camera.position.z
    }

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      context,
      antialias: false,
      alpha: false,
      powerPreference: "low-power"
    })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.25))

    this.group = new THREE.Group()
    this.scene.add(this.group)

    const positionArray = new Float32Array(coordinates.flatMap((point) => [point.x, point.y, point.z]))
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.BufferAttribute(positionArray, 3))
    geometry.computeBoundingSphere()

    this.group.add(new THREE.Line(
      geometry,
      new THREE.LineBasicMaterial({ color: this.colors.aqua, linewidth: 1 })
    ))

    const grid = new THREE.GridHelper(span * 2, 12, 0x2f5c57, 0x183532)
    grid.position.y = bounds.minY - 8
    this.group.add(grid)

    this.marker = new THREE.Mesh(
      new THREE.SphereGeometry(Math.max(span * 0.025, 2), 16, 16),
      new THREE.MeshBasicMaterial({ color: this.colors.amber })
    )
    this.group.add(this.marker)

    this.coordinates = coordinates
    this.drag = { active: false, x: 0, y: 0 }
    this.addSceneHandler("pointerdown", (event) => {
      this.drag = { active: true, x: event.clientX, y: event.clientY }
      this.sceneTarget.classList.add("is-dragging")
      canvas.setPointerCapture(event.pointerId)
    })
    this.addSceneHandler("pointermove", (event) => {
      if (!this.drag.active) return

      const dx = event.clientX - this.drag.x
      const dy = event.clientY - this.drag.y
      this.group.rotation.y += dx * 0.006
      this.group.rotation.x += dy * 0.003
      this.drag = { active: true, x: event.clientX, y: event.clientY }
      this.scheduleRender()
    })
    this.addSceneHandler("pointerup", () => {
      this.drag.active = false
      this.sceneTarget.classList.remove("is-dragging")
      this.scheduleRender()
    })
    this.addSceneHandler("pointercancel", () => {
      this.drag.active = false
      this.sceneTarget.classList.remove("is-dragging")
    })
    this.addSceneHandler("wheel", (event) => {
      event.preventDefault()
      const scale = event.deltaY > 0 ? 1.12 : 0.88
      this.camera.position.multiplyScalar(scale)
      this.camera.position.clampLength(span * 0.28, span * 5)
      this.camera.lookAt(0, 0, 0)
      this.scheduleRender()
    }, canvas, { passive: false })

    this.resizeObserver = new ResizeObserver(() => this.resizeScene())
    this.resizeObserver.observe(canvas)
    this.resizeScene()
  }

  async loadCesium() {
    if (window.Cesium) return window.Cesium

    await new Promise((resolve, reject) => {
      const existing = document.querySelector("script[data-sillage-cesium]")
      if (existing) {
        existing.addEventListener("load", resolve, { once: true })
        existing.addEventListener("error", reject, { once: true })
        return
      }

      const script = document.createElement("script")
      script.src = "https://cdn.jsdelivr.net/npm/cesium@1.124.0/Build/Cesium/Cesium.js"
      script.async = true
      script.dataset.sillageCesium = "true"
      script.addEventListener("load", resolve, { once: true })
      script.addEventListener("error", reject, { once: true })
      document.head.appendChild(script)
    })

    return window.Cesium
  }

  addCesiumTrajectory(Cesium, viewer) {
    const points = this.cesiumPoints()
    const positions = points.flatMap((point) => [point.lon, point.lat, this.cesiumAltitude(point)])
    const markerElapsed = this.currentElapsed
    const markerPoint = this.samplePointAtElapsed(markerElapsed, points) || points[0]
    const markerLabelPoint = this.samplePointAtElapsed(markerElapsed, this.points) || this.points[0]

    this.cesiumPath = viewer.entities.add({
      name: this.label("trajectory"),
      polyline: {
        positions: Cesium.Cartesian3.fromDegreesArrayHeights(positions),
        width: 5,
        material: new Cesium.PolylineGlowMaterialProperty({
          glowPower: 0.22,
          color: Cesium.Color.fromCssColorString(this.colors.aqua)
        })
      }
    })

    this.cesiumMarker = viewer.entities.add({
      name: this.label("current_position"),
      position: Cesium.Cartesian3.fromDegrees(markerPoint.lon, markerPoint.lat, this.cesiumAltitude(markerPoint)),
      point: {
        pixelSize: 14,
        color: Cesium.Color.fromCssColorString(this.colors.amber),
        outlineColor: Cesium.Color.WHITE,
        outlineWidth: 2,
        disableDepthTestDistance: Number.POSITIVE_INFINITY
      },
      label: {
        text: this.markerLabel(markerLabelPoint),
        font: "12px sans-serif",
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 2,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        showBackground: true,
        backgroundColor: Cesium.Color.fromCssColorString("rgba(7, 24, 23, 0.82)"),
        backgroundPadding: new Cesium.Cartesian2(8, 6),
        horizontalOrigin: Cesium.HorizontalOrigin.LEFT,
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        pixelOffset: new Cesium.Cartesian2(18, -18),
        disableDepthTestDistance: Number.POSITIVE_INFINITY
      }
    })

    this.addCesiumEventMarker(Cesium, viewer, "exit", this.boundsValue.exit)
    this.addCesiumEventMarker(Cesium, viewer, "opening", this.boundsValue.opening)
    this.addCesiumEventMarker(Cesium, viewer, "landing", this.boundsValue.landing)
  }

  addCesiumEventMarker(Cesium, viewer, key, elapsed) {
    const point = this.pointAtElapsed(elapsed, this.cesiumPoints())
    if (!point) return

    viewer.entities.add({
      name: this.label(key),
      position: Cesium.Cartesian3.fromDegrees(point.lon, point.lat, this.cesiumAltitude(point)),
      point: {
        pixelSize: 10,
        color: Cesium.Color.fromCssColorString(this.colors.coral),
        outlineColor: Cesium.Color.WHITE,
        outlineWidth: 1,
        disableDepthTestDistance: Number.POSITIVE_INFINITY
      },
      label: {
        text: this.label(key),
        font: "13px sans-serif",
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 2,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(0, -22),
        disableDepthTestDistance: Number.POSITIVE_INFINITY
      }
    })
  }

  configureCesiumDaylight(Cesium, viewer) {
    const scene = viewer.scene
    scene.backgroundColor = Cesium.Color.fromCssColorString(this.colors.daySky)
    if (scene.skyBox) scene.skyBox.show = false
    if (scene.moon) scene.moon.show = false
    if (scene.sun) scene.sun.show = true
    if (scene.skyAtmosphere) scene.skyAtmosphere.show = false
  }

  async pointsLiftedAboveCesiumSurface(Cesium, viewer, tileset) {
    const fallback = this.points.map((point) => ({ ...point, visualAlt: point.alt }))

    if (!viewer.scene.sampleHeightSupported || typeof viewer.scene.sampleHeightMostDetailed !== "function") {
      return fallback
    }

    try {
      if (tileset.readyPromise) await tileset.readyPromise

      const cartographics = this.points.map((point) =>
        Cesium.Cartographic.fromDegrees(point.lon, point.lat, point.alt)
      )
      const sampled = await viewer.scene.sampleHeightMostDetailed(cartographics, [], 2.0)
      const sampledHeights = sampled.map((position) => this.number(position?.height))
      const datumOffset = this.cesiumDatumOffsetFromSurface(sampledHeights)

      return this.points.map((point, index) => {
        const sampledHeight = sampledHeights[index]
        const datumAltitude = point.alt + datumOffset
        const visualAlt = Number.isFinite(sampledHeight)
          ? Math.max(datumAltitude, sampledHeight + this.cesiumSurfaceClearance(index))
          : datumAltitude

        return { ...point, groundAlt: sampledHeight, visualAlt, datumOffset }
      })
    } catch (error) {
      console.warn(`Cesium surface sampling unavailable: ${error.message || error}`)
      return fallback
    }
  }

  cesiumDatumOffsetFromSurface(sampledHeights) {
    const landingIndex = this.points.length - 1
    const landingGroundHeight = sampledHeights[landingIndex]
    if (!Number.isFinite(landingGroundHeight)) return 0

    const landingAltitude = this.number(this.points[landingIndex]?.alt)
    if (!Number.isFinite(landingAltitude)) return 0

    return this.clamp(landingGroundHeight + this.cesiumSurfaceClearance(landingIndex) - landingAltitude, 0, 120)
  }

  cesiumSurfaceClearance(index) {
    if (index === 0 || index === this.points.length - 1) return 10

    const elapsed = this.number(this.points[index]?.t)
    const opening = this.number(this.boundsValue.opening)
    const landing = this.number(this.boundsValue.landing)
    if (elapsed && opening && elapsed >= opening) return 8
    if (elapsed && landing && Math.abs(elapsed - landing) < 2) return 10

    return 18
  }

  configureCesiumCameraController(viewer) {
    const controller = viewer.scene.screenSpaceCameraController
    controller.enableCollisionDetection = false
    controller.enableInputs = false
    controller.enableLook = false
    controller.enableRotate = false
    controller.enableTilt = false
    controller.enableTranslate = false
    controller.enableZoom = false
  }

  setupCesiumMouseControls(Cesium, viewer) {
    if (this.cesiumInteractionHandler && !this.cesiumInteractionHandler.isDestroyed()) {
      this.cesiumInteractionHandler.destroy()
    }

    const handler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas)
    this.cesiumInteractionHandler = handler
    this.addSceneHandler("wheel", (event) => event.preventDefault(), viewer.scene.canvas, { passive: false })

    handler.setInputAction((movement) => {
      this.cesiumDrag = {
        active: true,
        x: movement.position.x,
        y: movement.position.y
      }
      this.sceneTarget.classList.add("is-dragging")
    }, Cesium.ScreenSpaceEventType.LEFT_DOWN)

    handler.setInputAction((movement) => {
      if (!this.cesiumDrag?.active || !this.cesiumOrbit) return

      const position = movement.endPosition
      const dx = position.x - this.cesiumDrag.x
      const dy = position.y - this.cesiumDrag.y
      this.cesiumDrag = { active: true, x: position.x, y: position.y }
      this.cesiumOrbit.heading -= dx * 0.006
      this.cesiumOrbit.pitch = this.clamp(
        this.cesiumOrbit.pitch + dy * 0.004,
        Cesium.Math.toRadians(-82),
        Cesium.Math.toRadians(-8)
      )
      this.applyCesiumOrbit(Cesium, viewer)
    }, Cesium.ScreenSpaceEventType.MOUSE_MOVE)

    handler.setInputAction(() => this.endCesiumDrag(), Cesium.ScreenSpaceEventType.LEFT_UP)
    handler.setInputAction(() => this.resetCamera(), Cesium.ScreenSpaceEventType.LEFT_DOUBLE_CLICK)
    handler.setInputAction((delta) => {
      if (!this.cesiumOrbit) return

      const wheel = typeof delta === "number" ? delta : delta?.deltaY || 0
      const factor = wheel > 0 ? 1.12 : 0.88
      this.cesiumOrbit.range = this.clamp(
        this.cesiumOrbit.range * factor,
        this.cesiumOrbit.minRange,
        this.cesiumOrbit.maxRange
      )
      this.applyCesiumOrbit(Cesium, viewer)
    }, Cesium.ScreenSpaceEventType.WHEEL)
  }

  endCesiumDrag() {
    this.cesiumDrag = { active: false, x: 0, y: 0 }
    this.sceneTarget.classList.remove("is-dragging")
  }

  flyCesiumCamera(Cesium, viewer) {
    const visualPoints = this.cesiumPoints()
    const start = visualPoints[0]
    const end = visualPoints[visualPoints.length - 1]
    const routeDistance = this.routeDistanceMeters()
    const heading = this.flightHeadingRadians(start, end) + Math.PI
    const range = this.clamp(routeDistance * 0.7, 420, 5_600)
    const focus = this.pointAtElapsed(this.boundsValue.exit, visualPoints) || start

    this.cesiumOrbitHome = {
      targetPoint: focus,
      heading,
      pitch: Cesium.Math.toRadians(-22),
      range,
      minRange: 40,
      maxRange: Math.max(range * 5, 1_600)
    }
    this.cesiumOrbit = { ...this.cesiumOrbitHome }
    this.applyCesiumOrbit(Cesium, viewer)
  }

  applyCesiumOrbit(Cesium, viewer) {
    if (!this.cesiumOrbit?.targetPoint) return

    const target = this.cesiumOrbit.targetPoint
    const targetPosition = Cesium.Cartesian3.fromDegrees(target.lon, target.lat, this.cesiumAltitude(target) + 18)
    viewer.camera.lookAt(
      targetPosition,
      new Cesium.HeadingPitchRange(
        this.cesiumOrbit.heading,
        this.cesiumOrbit.pitch,
        this.cesiumOrbit.range
      )
    )
    viewer.camera.lookAtTransform(Cesium.Matrix4.IDENTITY)
    viewer.scene.requestRender()
  }

  createTimeChart(target, datasets, scales) {
    const usableDatasets = datasets.filter((dataset) => dataset.data.length > 0)
    if (usableDatasets.length === 0) {
      this.hideChartPanel(target)
      return
    }

    this.createChart(target, {
      type: "line",
      data: { datasets: usableDatasets },
      options: this.chartOptions({ x: this.timeAxis(), ...scales }, true)
    })
  }

  createChart(target, config) {
    this.sizeChartCanvas(target)
    const chart = new this.Chart(target, config)
    this.charts.push(chart)
    this.installChartSync(chart)
  }

  chartOptions(scales, showBounds, cursorMode = "time") {
    return {
      animation: false,
      maintainAspectRatio: false,
      normalized: true,
      parsing: false,
      responsive: false,
      events: [],
      interaction: { mode: "nearest", axis: "x", intersect: false },
      elements: {
        line: { borderWidth: 2 },
        point: { radius: 0, hoverRadius: 3 }
      },
      plugins: {
        legend: { labels: { boxWidth: 10, usePointStyle: true } },
        tooltip: {
          callbacks: {
            title: (items) => this.formatTimer(this.chartItemElapsed(items[0]))
          }
        },
        sillageBounds: showBounds ? { bounds: this.boundsValue, labels: this.labelsValue } : false,
        sillagePlayback: {
          elapsed: this.currentElapsed,
          mode: cursorMode,
          color: this.colors.amber,
          pointColor: this.colors.coral
        }
      },
      scales
    }
  }

  installChartSync(chart) {
    const canvas = chart.canvas
    this.addSceneHandler("pointermove", (event) => {
      if (this.isPlaying && event.buttons === 0) return
      if (event.buttons > 0) this.pausePlayback()

      this.updateFromChartEvent(chart, event)
    }, canvas)
    this.addSceneHandler("pointerdown", (event) => {
      this.pausePlayback()
      canvas.setPointerCapture?.(event.pointerId)
      this.updateFromChartEvent(chart, event)
    }, canvas)
    this.addSceneHandler("pointerup", (event) => {
      canvas.releasePointerCapture?.(event.pointerId)
    }, canvas)
    this.addSceneHandler("pointercancel", (event) => {
      canvas.releasePointerCapture?.(event.pointerId)
    }, canvas)
  }

  updateFromChartEvent(chart, event) {
    const elapsed = this.elapsedFromChartEvent(chart, event)
    if (!Number.isFinite(elapsed)) return

    this.updateScrubbedElapsed(elapsed, { followCamera: false })
  }

  elapsedFromChartEvent(chart, event) {
    const position = this.chartEventPosition(chart, event)
    if (!position || !this.positionInsideChartArea(chart, position)) return null

    if (this.chartCursorMode(chart) === "track") {
      return this.elapsedFromTrackChartPosition(chart, position)
    }

    const elapsed = chart.scales?.x?.getValueForPixel(position.x)
    return Number.isFinite(Number(elapsed)) ? this.clamp(Number(elapsed), 0, this.flightDuration || 0) : null
  }

  chartEventPosition(chart, event) {
    const rect = chart.canvas.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return null

    return {
      x: (event.clientX - rect.left) * (chart.width / rect.width),
      y: (event.clientY - rect.top) * (chart.height / rect.height)
    }
  }

  positionInsideChartArea(chart, position) {
    const area = chart.chartArea
    if (!area) return false

    return position.x >= area.left && position.x <= area.right && position.y >= area.top && position.y <= area.bottom
  }

  elapsedFromTrackChartPosition(chart, position) {
    let closestElapsed = null
    let closestDistance = Number.POSITIVE_INFINITY

    chart.data.datasets.forEach((dataset, datasetIndex) => {
      const meta = chart.getDatasetMeta(datasetIndex)
      dataset.data.forEach((point, index) => {
        const element = meta.data[index]
        const x = this.number(element?.x)
        const y = this.number(element?.y)
        const elapsed = this.dataElapsed(point)
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(elapsed)) return

        const distance = ((x - position.x) ** 2) + ((y - position.y) ** 2)
        if (distance >= closestDistance) return

        closestDistance = distance
        closestElapsed = elapsed
      })
    })

    return closestElapsed
  }

  chartCursorMode(chart) {
    return chart.options?.plugins?.sillagePlayback?.mode || "time"
  }

  chartItemElapsed(item) {
    return this.dataElapsed(item?.raw) ?? this.number(item?.parsed?.x)
  }

  dataElapsed(point) {
    const elapsed = this.number(point?.t)
    if (Number.isFinite(elapsed)) return elapsed

    return this.number(point?.x)
  }

  dataset(label, rows, key, color, axis) {
    return {
      label,
      data: rows.map((row) => ({ x: this.number(row.t), y: this.number(row[key]) }))
        .filter((point) => Number.isFinite(point.x) && Number.isFinite(point.y)),
      borderColor: color,
      backgroundColor: color,
      yAxisID: axis,
      spanGaps: true,
      tension: 0.2
    }
  }

  sensorDataset(key, rows, label, color, axis) {
    return {
      label,
      data: rows.map((row) => ({ x: this.number(row.t), y: this.number(row.readings?.[key]) }))
        .filter((point) => Number.isFinite(point.x) && Number.isFinite(point.y)),
      borderColor: color,
      backgroundColor: color,
      yAxisID: axis,
      spanGaps: true,
      tension: 0.15
    }
  }

  sensorRows(type) {
    return this.sensors.filter((sample) => sample.type === type)
  }

  timeAxis() {
    return {
      type: "linear",
      position: "bottom",
      title: { display: true, text: this.label("time") },
      ticks: {
        maxTicksLimit: 8,
        callback: (value) => this.formatTimer(value)
      }
    }
  }

  axis(position, title, drawGrid = true) {
    return {
      type: "linear",
      position,
      title: { display: true, text: title },
      grid: { drawOnChartArea: drawGrid },
      ticks: { maxTicksLimit: 6 }
    }
  }

  addSceneHandler(eventName, handler, target = this.sceneCanvas, options = undefined) {
    target.addEventListener(eventName, handler, options)
    this.boundSceneHandlers.push([eventName, handler, target, options])
  }

  sizeChartCanvas(target) {
    const pixelRatio = Math.min(window.devicePixelRatio || 1, 1.5)
    const rect = target.getBoundingClientRect()
    const width = Math.max(Math.floor(rect.width), 320)
    const height = Math.max(Math.floor(rect.height), 260)

    target.width = Math.floor(width * pixelRatio)
    target.height = Math.floor(height * pixelRatio)
    target.style.width = `${width}px`
    target.style.height = `${height}px`
  }

  webglContext(canvas) {
    return canvas.getContext("webgl2", {
      antialias: false,
      powerPreference: "low-power"
    }) || canvas.getContext("webgl", {
      antialias: false,
      powerPreference: "low-power"
    })
  }

  showSceneFallback(canvas) {
    const context = canvas.getContext("2d")
    const width = canvas.clientWidth || 640
    const height = canvas.clientHeight || 360
    canvas.width = width
    canvas.height = height
    if (!context) return

    context.fillStyle = this.colors.daySky
    context.fillRect(0, 0, width, height)
    context.strokeStyle = this.colors.aqua
    context.lineWidth = 2
    context.beginPath()
    const heights = this.points.map((row) => this.heightFromGround(row) ?? 0)
    const heightSpan = Math.max(Math.max(...heights), 1)
    this.points.forEach((point, index) => {
      const x = (index / Math.max(this.points.length - 1, 1)) * width
      const y = height - ((this.heightFromGround(point) ?? 0) / heightSpan) * height * 0.78 - 24
      if (index === 0) context.moveTo(x, y)
      else context.lineTo(x, y)
    })
    context.stroke()
    context.fillStyle = this.colors.night
    context.font = "14px sans-serif"
    context.fillText(this.label("webgl_unavailable"), 18, 28)
  }

  showSceneFallbackMessage(message) {
    const note = document.createElement("div")
    note.className = "trajectory-notice"
    note.textContent = message
    this.sceneTarget.appendChild(note)
  }

  resizeScene() {
    if (!this.renderer || !this.sceneCanvas) return

    const width = this.sceneTarget.clientWidth
    const height = this.sceneTarget.clientHeight
    if (width === 0 || height === 0) return

    this.renderer.setSize(width, height, false)
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    this.scheduleRender()
  }

  scheduleRender() {
    if (this.renderFrame || !this.renderer || !this.scene || !this.camera) return

    this.renderFrame = requestAnimationFrame(() => {
      this.renderFrame = null
      this.renderer.render(this.scene, this.camera)
    })
  }

  updateScrubbedPoint(ratio) {
    this.updateScrubbedElapsed(ratio * this.flightDuration)
  }

  updateScrubbedElapsed(elapsed, options = {}) {
    const followCamera = options.followCamera !== false
    const syncVideo = options.syncVideo !== false
    const clampedElapsed = this.clamp(elapsed || 0, 0, this.flightDuration || 0)
    const point = this.samplePointAtElapsed(clampedElapsed, this.points)
    const visualPoint = this.samplePointAtElapsed(clampedElapsed, this.cesiumPoints()) || point
    const coordinate = this.sampleCoordinateAtElapsed(clampedElapsed)
    this.currentElapsed = clampedElapsed

    if (this.hasScrubberTarget && this.flightDuration > 0) {
      this.scrubberTarget.value = Math.round((clampedElapsed / this.flightDuration) * 1000)
    }

    if (visualPoint && this.cesiumMarker && window.Cesium) {
      this.cesiumMarker.position = window.Cesium.Cartesian3.fromDegrees(
        visualPoint.lon,
        visualPoint.lat,
        this.cesiumAltitude(visualPoint)
      )
      this.cesiumMarker.label.text = this.markerLabel(point)
      if (followCamera && this.cesiumOrbit) {
        this.cesiumOrbit.targetPoint = visualPoint
        this.applyCesiumOrbit(window.Cesium, this.cesiumViewer)
      }
      this.cesiumViewer?.scene.requestRender()
    }

    if (coordinate && this.marker) {
      this.marker.position.set(coordinate.x, coordinate.y, coordinate.z)
      this.scheduleRender()
    }
    if (this.hasTimeLabelTarget) this.timeLabelTarget.textContent = this.playbackTimeLabel(clampedElapsed)
    this.updateChartsPlaybackCursor(clampedElapsed)
    if (syncVideo) this.syncVideoToElapsed(clampedElapsed)
  }

  updateChartsPlaybackCursor(elapsed) {
    this.charts.forEach((chart) => {
      const playback = chart.options?.plugins?.sillagePlayback
      if (!playback) return

      playback.elapsed = elapsed
      const activeElements = this.chartActiveElementsAtElapsed(chart, elapsed)
      chart.setActiveElements(activeElements)
      chart.tooltip?.setActiveElements(activeElements, this.chartTooltipPosition(chart, activeElements, elapsed))
      chart.update("none")
    })
  }

  chartActiveElementsAtElapsed(chart, elapsed) {
    return chart.data.datasets.filter((dataset) => dataset.data.length > 0).map((dataset) => {
      const datasetIndex = chart.data.datasets.indexOf(dataset)
      const index = this.nearestDataIndexAtElapsed(dataset.data, elapsed)
      if (index === null) return null

      return { datasetIndex, index }
    }).filter(Boolean)
  }

  nearestDataIndexAtElapsed(data, elapsed) {
    if (!data?.length || !Number.isFinite(Number(elapsed))) return null

    let low = 0
    let high = data.length - 1

    while (low < high) {
      const middle = Math.floor((low + high) / 2)
      const middleElapsed = this.dataElapsed(data[middle])
      if (!Number.isFinite(middleElapsed)) return this.nearestDataIndexAtElapsedLinear(data, elapsed)
      if (middleElapsed < elapsed) low = middle + 1
      else high = middle
    }

    const candidates = [ low, low - 1, low + 1 ].filter((index) => index >= 0 && index < data.length)
    return candidates.reduce((closestIndex, index) => {
      if (closestIndex === null) return index

      const closestDistance = Math.abs(this.dataElapsed(data[closestIndex]) - elapsed)
      const distance = Math.abs(this.dataElapsed(data[index]) - elapsed)
      return distance < closestDistance ? index : closestIndex
    }, null)
  }

  nearestDataIndexAtElapsedLinear(data, elapsed) {
    return data.reduce((closestIndex, point, index) => {
      const pointElapsed = this.dataElapsed(point)
      if (!Number.isFinite(pointElapsed)) return closestIndex
      if (closestIndex === null) return index

      const closestDistance = Math.abs(this.dataElapsed(data[closestIndex]) - elapsed)
      const distance = Math.abs(pointElapsed - elapsed)
      return distance < closestDistance ? index : closestIndex
    }, null)
  }

  chartTooltipPosition(chart, activeElements, elapsed) {
    const firstElement = activeElements[0]
    if (firstElement) {
      const point = chart.getDatasetMeta(firstElement.datasetIndex)?.data?.[firstElement.index]
      if (point) return { x: point.x, y: point.y }
    }

    const area = chart.chartArea
    const x = chart.scales?.x?.getPixelForValue(elapsed)
    return {
      x: Number.isFinite(x) ? x : area?.left || 0,
      y: area ? area.top : 0
    }
  }

  disposeScene() {
    if (this.group) {
      this.group.traverse((object) => {
        if (object.geometry) object.geometry.dispose()
        if (object.material) object.material.dispose()
      })
    }
    if (this.renderer) {
      this.renderer.dispose()
      this.renderer.forceContextLoss()
    }

    this.scene = null
    this.camera = null
    this.renderer = null
    this.group = null
    this.localCameraHome = null
  }

  hideChartPanel(target) {
    target.closest(".chart-panel")?.setAttribute("hidden", "")
  }

  pointAtElapsed(elapsed, points = this.points) {
    if (!Number.isFinite(Number(elapsed))) return null

    return points.reduce((closest, point) => {
      if (!closest) return point

      const closestDistance = Math.abs(this.number(closest.t) - Number(elapsed))
      const pointDistance = Math.abs(this.number(point.t) - Number(elapsed))
      return pointDistance < closestDistance ? point : closest
    }, null)
  }

  samplePointAtElapsed(elapsed, points = this.points) {
    if (!points?.length) return null
    if (points.length === 1) return { ...points[0], t: elapsed }

    const firstTime = this.number(points[0].t) ?? 0
    if (elapsed <= firstTime) return { ...points[0], t: elapsed }

    for (let index = 1; index < points.length; index += 1) {
      const previous = points[index - 1]
      const next = points[index]
      const previousTime = this.number(previous.t) ?? 0
      const nextTime = this.number(next.t) ?? previousTime
      if (elapsed > nextTime) continue

      const span = Math.max(nextTime - previousTime, 0.001)
      return this.interpolatePoint(previous, next, (elapsed - previousTime) / span, elapsed)
    }

    return { ...points[points.length - 1], t: elapsed }
  }

  sampleCoordinateAtElapsed(elapsed) {
    if (!this.coordinates?.length) return null
    if (this.coordinates.length === 1) return this.coordinates[0]

    const firstTime = this.number(this.points[0]?.t) ?? 0
    if (elapsed <= firstTime) return this.coordinates[0]

    for (let index = 1; index < this.coordinates.length; index += 1) {
      const previousTime = this.number(this.points[index - 1]?.t) ?? 0
      const nextTime = this.number(this.points[index]?.t) ?? previousTime
      if (elapsed > nextTime) continue

      const ratio = (elapsed - previousTime) / Math.max(nextTime - previousTime, 0.001)
      return {
        x: this.lerp(this.coordinates[index - 1].x, this.coordinates[index].x, ratio),
        y: this.lerp(this.coordinates[index - 1].y, this.coordinates[index].y, ratio),
        z: this.lerp(this.coordinates[index - 1].z, this.coordinates[index].z, ratio)
      }
    }

    return this.coordinates[this.coordinates.length - 1]
  }

  interpolatePoint(previous, next, ratio, elapsed) {
    const point = { ...previous, t: elapsed }
    const keys = ["lat", "lon", "alt", "height", "hspeed", "vspeed", "glide", "distance", "visualAlt", "groundAlt", "datumOffset"]

    keys.forEach((key) => {
      const a = this.number(previous[key])
      const b = this.number(next[key])
      if (Number.isFinite(a) && Number.isFinite(b)) point[key] = this.lerp(a, b, ratio)
    })

    return point
  }

  lerp(a, b, ratio) {
    return a + ((b - a) * ratio)
  }

  designColors() {
    const styles = getComputedStyle(document.documentElement)
    return {
      night: styles.getPropertyValue("--ds-night").trim() || "#071817",
      daySky: "#b9dcf2",
      aqua: styles.getPropertyValue("--ds-aqua").trim() || "#28bfb8",
      teal: styles.getPropertyValue("--ds-teal").trim() || "#007f78",
      amber: styles.getPropertyValue("--ds-amber").trim() || "#d89122",
      violet: styles.getPropertyValue("--ds-violet").trim() || "#6658c7",
      coral: styles.getPropertyValue("--ds-coral").trim() || "#e85d4f",
      lime: styles.getPropertyValue("--ds-lime").trim() || "#a7c83f"
    }
  }

  localCoordinates() {
    const first = this.points[0]
    const lat0 = first.lat * Math.PI / 180
    const metersPerDegreeLat = 111_320
    const metersPerDegreeLon = Math.cos(lat0) * 111_320

    const raw = this.points.map((point) => ({
      x: (point.lon - first.lon) * metersPerDegreeLon,
      y: (this.heightFromGround(point) ?? 0) * 0.45,
      z: -(point.lat - first.lat) * metersPerDegreeLat
    }))

    const center = this.center(raw)
    return raw.map((point) => ({
      x: point.x - center.x,
      y: point.y - center.y,
      z: point.z - center.z
    }))
  }

  coordinateBounds(points) {
    const xs = points.map((point) => point.x)
    const ys = points.map((point) => point.y)
    const zs = points.map((point) => point.z)
    const minY = Math.min(...ys)

    return {
      x: Math.max(...xs) - Math.min(...xs),
      y: Math.max(...ys) - minY,
      z: Math.max(...zs) - Math.min(...zs),
      minY
    }
  }

  center(points) {
    const bounds = this.coordinateBounds(points)
    const xs = points.map((point) => point.x)
    const ys = points.map((point) => point.y)
    const zs = points.map((point) => point.z)

    return {
      x: Math.min(...xs) + bounds.x / 2,
      y: Math.min(...ys) + bounds.y / 2,
      z: Math.min(...zs) + bounds.z / 2
    }
  }

  cesiumPoints() {
    return this.cesiumVisualPoints || this.points
  }

  cesiumAltitude(point) {
    return this.number(point?.visualAlt) ?? this.number(point?.alt) ?? 0
  }

  routeDistanceMeters() {
    const finalDistance = this.number(this.points[this.points.length - 1]?.distance)
    if (finalDistance) return finalDistance

    const first = this.points[0]
    const last = this.points[this.points.length - 1]
    if (!first || !last) return 1_000

    const lat = ((first.lat + last.lat) / 2) * Math.PI / 180
    const dx = (last.lon - first.lon) * Math.cos(lat) * 111_320
    const dy = (last.lat - first.lat) * 111_320
    return Math.sqrt(dx ** 2 + dy ** 2)
  }

  flightHeadingRadians(start, end) {
    const lat1 = start.lat * Math.PI / 180
    const lat2 = end.lat * Math.PI / 180
    const dLon = (end.lon - start.lon) * Math.PI / 180
    const y = Math.sin(dLon) * Math.cos(lat2)
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon)
    return Math.atan2(y, x)
  }

  clamp(value, min, max) {
    return Math.min(max, Math.max(min, value))
  }

  durationFromPoints() {
    return Math.max(...this.points.map((point) => this.number(point.t) ?? 0), 0)
  }

  number(value) {
    const number = Number(value)
    return Number.isFinite(number) ? number : null
  }

  groundAltitudeFromPoints() {
    const altitudes = this.points.map((point) => this.number(point.alt)).filter((value) => Number.isFinite(value))
    if (!altitudes.length) return null

    return Math.min(...altitudes)
  }

  heightFromGround(point) {
    const height = this.number(point?.height)
    if (Number.isFinite(height)) return height

    const altitude = this.number(point?.alt)
    if (!Number.isFinite(altitude) || !Number.isFinite(this.groundAltitude)) return null

    return Math.max(altitude - this.groundAltitude, 0)
  }

  label(key) {
    return this.labelsValue[key] || key
  }

  markerLabel(point) {
    if (!point) return ""

    return [
      this.formatTimer(point.t),
      `${this.label("marker_height")} ${this.formatMetric(this.heightFromGround(point), this.label("meters"), 0)}  ` +
        `${this.label("marker_altitude")} ${this.formatMetric(point.alt, this.label("meters"), 0)}`,
      `${this.label("marker_hspeed")} ${this.formatMetric(point.hspeed, this.label("meters_per_second"), 1)}  ` +
        `${this.label("marker_vspeed")} ${this.formatMetric(point.vspeed, this.label("meters_per_second"), 1)}`,
      `${this.label("glide")} ${this.formatNumber(point.glide, 2)}`
    ].join("\n")
  }

  formatMetric(value, unit, digits) {
    const number = this.number(value)
    if (!Number.isFinite(number)) return `- ${unit}`

    return `${number.toFixed(digits)} ${unit}`
  }

  formatNumber(value, digits) {
    const number = this.number(value)
    return Number.isFinite(number) ? number.toFixed(digits) : "-"
  }

  playbackTimeLabel(elapsed) {
    return `${this.formatTimer(elapsed)} / ${this.formatSeconds(this.flightDurationFromExit())}`
  }

  formatTimer(elapsed) {
    const relativeElapsed = this.elapsedFromExit(elapsed)
    if (!Number.isFinite(relativeElapsed)) return "T --:--"

    const prefix = relativeElapsed < 0 ? "T-" : "T+"
    return `${prefix}${this.formatSeconds(Math.abs(relativeElapsed))}`
  }

  formatSeconds(value) {
    const seconds = Math.max(0, Math.round(value || 0))
    const minutes = Math.floor(seconds / 60)
    return `${String(minutes).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`
  }

  elapsedFromExit(elapsed) {
    const elapsedSeconds = this.number(elapsed)
    if (!Number.isFinite(elapsedSeconds)) return null

    return elapsedSeconds - this.exitElapsed()
  }

  exitElapsed() {
    const exit = this.number(this.boundsValue?.exit)
    return Number.isFinite(exit) ? exit : 0
  }

  flightDurationFromExit() {
    return Math.max(0, (this.flightDuration || 0) - this.exitElapsed())
  }

  defaultElapsed() {
    return this.clamp(this.exitElapsed(), 0, this.flightDuration || 0)
  }
}

const SILLAGE_BOUNDS_PLUGIN = {
  id: "sillageBounds",
  afterDatasetsDraw(chart, _args, options) {
    if (!options?.bounds) return

    const area = chart.chartArea
    const xScale = chart.scales?.x
    if (!xScale || !area) return

    const ctx = chart.ctx
    const labels = options.labels || {}
    const bounds = [
      ["exit", options.bounds.exit],
      ["opening", options.bounds.opening],
      ["landing", options.bounds.landing]
    ].filter(([, value]) => Number.isFinite(Number(value)))

    ctx.save()
    ctx.textBaseline = "top"
    ctx.font = "11px sans-serif"
    bounds.forEach(([key, value]) => {
      const x = xScale.getPixelForValue(Number(value))
      if (x < area.left || x > area.right) return

      ctx.strokeStyle = "rgba(232, 93, 79, 0.48)"
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(x, area.top)
      ctx.lineTo(x, area.bottom)
      ctx.stroke()

      ctx.fillStyle = "rgba(22, 35, 32, 0.72)"
      ctx.fillText(labels[key] || key, x + 4, area.top + 4)
    })
    ctx.restore()
  }
}

const SILLAGE_PLAYBACK_PLUGIN = {
  id: "sillagePlayback",
  afterDatasetsDraw(chart, _args, options) {
    const elapsed = Number(options?.elapsed)
    if (!Number.isFinite(elapsed)) return

    const area = chart.chartArea
    const xScale = chart.scales?.x
    if (!xScale || !area) return

    const ctx = chart.ctx
    ctx.save()
    ctx.strokeStyle = options.color || "rgba(216, 145, 34, 0.9)"
    ctx.lineWidth = 2
    if ((options.mode || "time") !== "track") {
      const x = xScale.getPixelForValue(elapsed)
      if (x >= area.left && x <= area.right) {
        ctx.beginPath()
        ctx.moveTo(x, area.top)
        ctx.lineTo(x, area.bottom)
        ctx.stroke()
      }
    }

    ctx.fillStyle = options.pointColor || options.color || "rgba(216, 145, 34, 0.9)"
    ctx.strokeStyle = "rgba(255, 255, 255, 0.92)"
    chart.getActiveElements().forEach(({ datasetIndex, index }) => {
      const point = chart.getDatasetMeta(datasetIndex)?.data?.[index]
      if (!point) return
      if (point.x < area.left || point.x > area.right || point.y < area.top || point.y > area.bottom) return

      ctx.beginPath()
      ctx.arc(point.x, point.y, 4, 0, Math.PI * 2)
      ctx.fill()
      ctx.lineWidth = 1.5
      ctx.stroke()
    })
    ctx.restore()
  }
}
