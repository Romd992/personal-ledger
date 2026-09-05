package com.personal.ledger

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class MainActivity : FlutterActivity() {
    private val FILE_CHANNEL = "com.personal.ledger/filesearch"
    private val BT_CHANNEL = "com.personal.ledger/bluetooth"

    // SPP 标准 UUID
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val REQUEST_ENABLE_BT = 1001

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bm.adapter
    }

    private var bluetoothSocket: BluetoothSocket? = null
    private var serverSocket: BluetoothServerSocket? = null
    private val discoveredDevices = mutableListOf<Map<String, Any>>()
    private val isSearching = AtomicBoolean(false)
    private val isConnected = AtomicBoolean(false)
    private val isServerMode = AtomicBoolean(false)
    private val transferProgress = AtomicLong(0)
    private val transferTotal = AtomicLong(0)
    private val isTransferring = AtomicBoolean(false)

    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    device?.let {
                        val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (ActivityCompat.checkSelfPermission(this@MainActivity, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) it.name else it.address
                        } else {
                            @Suppress("DEPRECATION") it.name ?: it.address
                        }
                        val exists = discoveredDevices.any { d -> d["address"] == it.address }
                        if (!exists) {
                            discoveredDevices.add(mapOf("name" to (name ?: it.address), "address" to it.address))
                        }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    isSearching.set(false)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ===== 文件搜索 Channel =====
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "searchBackupFiles" -> {
                    val keywords = call.argument<List<String>>("keywords")
                        ?: listOf("ledger", "简帐备份", "个人记账备份", "auto_", "记账备份")
                    result.success(searchBackupFiles(keywords))
                }
                "readFileBytes" -> {
                    val uriString = call.argument<String>("uri") ?: ""
                    result.success(readFileBytes(uriString))
                }
                "openFolder" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(openFolder(path))
                }
                else -> result.notImplemented()
            }
        }

        // ===== 蓝牙 Channel =====
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBluetoothAvailable" -> result.success(isBluetoothAvailable())
                "requestEnableBluetooth" -> { requestEnableBluetooth(); result.success(true) }
                "startDiscovery" -> result.success(startDiscovery())
                "cancelDiscovery" -> { cancelDiscovery(); result.success(true) }
                "getDiscoveredDevices" -> result.success(ArrayList(discoveredDevices))
                "getPairedDevices" -> result.success(getPairedDevices())
                "connectToDevice" -> {
                    val address = call.argument<String>("address") ?: ""
                    result.success(connectToDevice(address))
                }
                "startServer" -> result.success(startServer())
                "sendFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    result.success(sendFile(filePath))
                }
                "receiveFile" -> {
                    val saveDir = call.argument<String>("saveDir") ?: ""
                    result.success(receiveFile(saveDir))
                }
                "disconnect" -> { disconnect(); result.success(true) }
                "getConnectionStatus" -> result.success(mapOf(
                    "connected" to isConnected.get(),
                    "isServer" to isServerMode.get(),
                    "searching" to isSearching.get(),
                    "transferring" to isTransferring.get(),
                    "progress" to transferProgress.get(),
                    "total" to transferTotal.get()
                ))
                "getDeviceName" -> result.success(getDeviceName())
                else -> result.notImplemented()
            }
        }

        // 注册蓝牙搜索广播
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        registerReceiver(discoveryReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(discoveryReceiver) } catch (_: Exception) {}
        disconnect()
    }

    // ========== 文件搜索方法 ==========
    private fun searchBackupFiles(keywords: List<String>): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        try {
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED
            )
            val sel = keywords.joinToString(" OR ") { "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?" }
            val args = keywords.map { "%$it%" }.toTypedArray()
            val sortOrder = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
            contentResolver.query(MediaStore.Files.getContentUri("external"), projection, sel, args, sortOrder)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    val name = c.getString(1) ?: continue
                    val size = c.getLong(2)
                    val date = c.getLong(3)
                    val uri = android.content.ContentUris.withAppendedId(MediaStore.Files.getContentUri("external"), id).toString()
                    if (seen.add(uri)) results.add(mapOf("name" to name, "size" to size, "dateModified" to date, "uri" to uri, "source" to "MediaStore"))
                }
            }
        } catch (_: Exception) {}
        listOf("简帐备份", "个人记账备份").forEach { dirName ->
            try {
                val dir = File(getExternalFilesDir(null), dirName)
                if (dir.exists()) {
                    dir.listFiles()?.forEach { f ->
                        if (f.isFile && keywords.any { f.name.contains(it, ignoreCase = true) }) {
                            val uri = Uri.fromFile(f).toString()
                            if (seen.add(uri)) results.add(mapOf("name" to f.name, "size" to f.length(), "dateModified" to f.lastModified() / 1000, "uri" to uri, "source" to "AppBackup"))
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        results.sortByDescending { it["dateModified"] as Long }
        return results
    }

    private fun readFileBytes(uriString: String): ByteArray? {
        return try { contentResolver.openInputStream(Uri.parse(uriString))?.use { it.readBytes() } } catch (_: Exception) { null }
    }

    private fun openFolder(path: String): String {
        return try {
            val folder = File(path)
            if (!folder.exists()) folder.mkdirs()
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setDataAndType(Uri.fromFile(folder), "resource/folder")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            "ok"
        } catch (e: Exception) {
            try {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(Uri.fromFile(File(path)), "vnd.android.document/directory")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                "ok"
            } catch (e2: Exception) { "error: ${e2.message}" }
        }
    }

    // ========== 蓝牙方法 ==========
    private fun isBluetoothAvailable(): Boolean {
        return try {
            val adapter = bluetoothAdapter
            adapter != null && adapter.isEnabled
        } catch (_: Exception) { false }
    }

    private fun requestEnableBluetooth() {
        try {
            val adapter = bluetoothAdapter
            if (adapter != null && !adapter.isEnabled) {
                val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                startActivityForResult(intent, REQUEST_ENABLE_BT)
            }
        } catch (_: Exception) {}
    }

    private fun getDeviceName(): String {
        return try {
            val adapter = bluetoothAdapter ?: return "未知设备"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED)
                    adapter.name ?: "未知设备" else "未知设备"
            } else {
                @Suppress("DEPRECATION") adapter.name ?: "未知设备"
            }
        } catch (_: Exception) { "未知设备" }
    }

    private fun startDiscovery(): Boolean {
        return try {
            val adapter = bluetoothAdapter ?: return false
            discoveredDevices.clear()
            isSearching.set(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) return false
            }
            adapter.startDiscovery()
            true
        } catch (_: Exception) {
            isSearching.set(false)
            false
        }
    }

    private fun cancelDiscovery() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED)
                    bluetoothAdapter?.cancelDiscovery()
            } else {
                @Suppress("DEPRECATION") bluetoothAdapter?.cancelDiscovery()
            }
        } catch (_: Exception) {}
        isSearching.set(false)
    }

    private fun getPairedDevices(): List<Map<String, Any>> {
        return try {
            val adapter = bluetoothAdapter ?: return emptyList()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return emptyList()
            }
            adapter.bondedDevices.map {
                mapOf("name" to (it.name ?: it.address), "address" to it.address)
            }.toList()
        } catch (_: Exception) { emptyList() }
    }

    private fun connectToDevice(address: String): Boolean {
        return try {
            val adapter = bluetoothAdapter ?: return false
            if (address.isEmpty()) return false
            cancelDiscovery()
            val device = adapter.getRemoteDevice(address)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return false
            }
            bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            bluetoothSocket?.connect()
            isConnected.set(true)
            isServerMode.set(false)
            true
        } catch (e: Exception) {
            isConnected.set(false)
            false
        }
    }

    private fun startServer(): Boolean {
        return try {
            val adapter = bluetoothAdapter ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return false
            }
            serverSocket = adapter.listenUsingRfcommWithServiceRecord("简帐蓝牙传输", SPP_UUID)
            isServerMode.set(true)
            // 后台线程等待连接
            Thread {
                try {
                    bluetoothSocket = serverSocket?.accept()
                    isConnected.set(true)
                } catch (_: Exception) {
                    isConnected.set(false)
                }
            }.start()
            true
        } catch (e: Exception) {
            isServerMode.set(false)
            false
        }
    }

    private fun sendFile(filePath: String): Boolean {
        return try {
            val socket = bluetoothSocket ?: return false
            if (!socket.isConnected) return false
            val file = File(filePath)
            if (!file.exists()) return false

            isTransferring.set(true)
            transferProgress.set(0)
            transferTotal.set(file.length())

            val input = FileInputStream(file)
            val output = socket.outputStream

            // 协议：4字节文件名长度 + 文件名 + 8字节文件大小 + 文件数据
            val nameBytes = file.name.toByteArray(Charsets.UTF_8)
            val nameLen = nameBytes.size
            output.write(byteArrayOf(
                (nameLen shr 24).toByte(), (nameLen shr 16).toByte(),
                (nameLen shr 8).toByte(), nameLen.toByte()
            ))
            output.write(nameBytes)

            val fileSize = file.length()
            output.write(byteArrayOf(
                (fileSize shr 56).toByte(), (fileSize shr 48).toByte(),
                (fileSize shr 40).toByte(), (fileSize shr 32).toByte(),
                (fileSize shr 24).toByte(), (fileSize shr 16).toByte(),
                (fileSize shr 8).toByte(), fileSize.toByte()
            ))

            val buffer = ByteArray(16384)
            var bytesRead: Int
            var totalSent = 0L
            while (input.read(buffer).also { bytesRead = it } != -1) {
                output.write(buffer, 0, bytesRead)
                totalSent += bytesRead
                transferProgress.set(totalSent)
            }
            output.flush()
            input.close()
            isTransferring.set(false)
            true
        } catch (e: Exception) {
            isTransferring.set(false)
            false
        }
    }

    private fun receiveFile(saveDir: String): String? {
        return try {
            val socket = bluetoothSocket ?: return null
            if (!socket.isConnected) return null

            isTransferring.set(true)
            transferProgress.set(0)

            val input = socket.inputStream

            // 读取文件名长度
            val nameLenBytes = ByteArray(4)
            var offset = 0
            while (offset < 4) {
                val read = input.read(nameLenBytes, offset, 4 - offset)
                if (read == -1) break
                offset += read
            }
            val nameLen = ((nameLenBytes[0].toInt() and 0xFF) shl 24) or
                    ((nameLenBytes[1].toInt() and 0xFF) shl 16) or
                    ((nameLenBytes[2].toInt() and 0xFF) shl 8) or
                    (nameLenBytes[3].toInt() and 0xFF)

            // 读取文件名
            val nameBytes = ByteArray(nameLen)
            offset = 0
            while (offset < nameLen) {
                val read = input.read(nameBytes, offset, nameLen - offset)
                if (read == -1) break
                offset += read
            }
            val fileName = String(nameBytes, Charsets.UTF_8)

            // 读取文件大小
            val sizeBytes = ByteArray(8)
            offset = 0
            while (offset < 8) {
                val read = input.read(sizeBytes, offset, 8 - offset)
                if (read == -1) break
                offset += read
            }
            var fileSize = 0L
            for (i in 0..7) fileSize = (fileSize shl 8) or (sizeBytes[i].toLong() and 0xFF)
            transferTotal.set(fileSize)

            // 确保保存目录存在
            val dir = File(saveDir)
            if (!dir.exists()) dir.mkdirs()

            // 读取文件数据
            val file = File(dir, fileName)
            val output = FileOutputStream(file)
            val buffer = ByteArray(16384)
            var totalReceived = 0L
            while (totalReceived < fileSize) {
                val toRead = minOf(buffer.size, (fileSize - totalReceived).toInt())
                val bytesRead = input.read(buffer, 0, toRead)
                if (bytesRead == -1) break
                output.write(buffer, 0, bytesRead)
                totalReceived += bytesRead
                transferProgress.set(totalReceived)
            }
            output.close()
            isTransferring.set(false)
            file.absolutePath
        } catch (e: Exception) {
            isTransferring.set(false)
            null
        }
    }

    private fun disconnect() {
        try { bluetoothSocket?.close() } catch (_: Exception) {}
        try { serverSocket?.close() } catch (_: Exception) {}
        bluetoothSocket = null
        serverSocket = null
        isConnected.set(false)
        isServerMode.set(false)
        isTransferring.set(false)
    }
}
