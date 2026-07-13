package com.follow.clash

import android.app.Activity
import android.os.Bundle
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

class RuntimeMemoryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Service.bind()
        GlobalState.launch {
            val action =
                """{"id":"runtimeMemory#${System.currentTimeMillis()}","method":"getRuntimeMemory","data":null}"""
            val result = Service.invokeAction(action) {
                GlobalState.log("RuntimeMemory $it")
            }
            result.exceptionOrNull()?.let {
                GlobalState.log("RuntimeMemory error ${it.message}")
            }
            runOnUiThread { finish() }
        }
    }
}
