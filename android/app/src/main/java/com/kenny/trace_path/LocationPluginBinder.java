package com.kenny.trace_path;

import io.flutter.plugin.common.EventChannel;

/**
 * 用于在 Plugin 和 Service 之间传递 EventSink
 */
public class LocationPluginBinder {

    private static EventChannel.EventSink eventSink;

    public static void setEventSink(EventChannel.EventSink sink) {
        eventSink = sink;
    }

    public static EventChannel.EventSink getEventSink() {
        return eventSink;
    }
}
