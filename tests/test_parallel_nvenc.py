#!/usr/bin/env python3
"""
Test maximum parallel GStreamer NVENC encoding capacity using GI bindings
Uses bus.timed_pop_filtered() pattern from cam_handler (thread-safe, no GLib.MainLoop)

Uses videotestsrc with is-live=true and pattern=white to minimize CPU overhead:
- is-live=true: Respects 24fps timing (not push-as-fast-as-possible)
- pattern=white: Minimal CPU for pattern generation (~10% vs 100%)

NVENC settings match production low-latency requirements:
- preset=1: Low-latency preset (P1)
- zerolatency=true: Zero-latency encoding mode
- rc-mode=cbr: Constant bitrate (predictable GPU load)
- bitrate=5000: 5Mbps (typical for 1080p streaming)
- gop-size=60: 2.5 seconds at 24fps (lower latency)

Success criteria: All pipelines complete without errors within expected time
"""

import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
import time
import threading
from queue import Queue

# Initialize GStreamer
Gst.init(None)


class StreamEncoder:
    """Single GStreamer NVENC encoding stream"""

    def __init__(self, stream_id, duration_sec, results_queue):
        self.stream_id = stream_id
        self.duration_sec = duration_sec
        self.results_queue = results_queue
        self.pipeline = None
        self.bus = None
        self.start_time = None

    def run(self):
        """Run the encoding pipeline"""
        # Create pipeline matching production settings
        num_buffers = self.duration_sec * 24

        pipeline_str = (
            f"videotestsrc num-buffers={num_buffers} pattern=white is-live=true "
            "! video/x-raw,format=I420,width=1920,height=1080,framerate=24/1 "
            "! nvh264enc rc-mode=cbr bitrate=5000 preset=1 zerolatency=true gop-size=60 "
            "! video/x-h264,profile=baseline "
            "! fakesink"
        )

        try:
            # Create pipeline
            self.pipeline = Gst.parse_launch(pipeline_str)
            self.bus = self.pipeline.get_bus()

            # Start pipeline
            self.start_time = time.time()
            self.pipeline.set_state(Gst.State.PLAYING)

            # Poll bus for messages (cam_handler pattern - no GLib.MainLoop)
            finished = False
            error_msg = None

            while not finished:
                # Poll for ERROR or EOS messages
                message = self.bus.timed_pop_filtered(
                    0.1 * Gst.SECOND,
                    Gst.MessageType.ERROR | Gst.MessageType.EOS
                )

                if message:
                    msgType = message.type

                    if msgType == Gst.MessageType.EOS:
                        # Successfully completed
                        elapsed = time.time() - self.start_time
                        speed = self.duration_sec / elapsed if elapsed > 0 else 0.0

                        self.results_queue.put({
                            'stream_id': self.stream_id,
                            'success': True,
                            'elapsed': elapsed,
                            'speed': speed,
                            'error': None
                        })
                        finished = True

                    elif msgType == Gst.MessageType.ERROR:
                        # Error occurred
                        err, debug = message.parse_error()
                        elapsed = time.time() - self.start_time

                        self.results_queue.put({
                            'stream_id': self.stream_id,
                            'success': False,
                            'elapsed': elapsed,
                            'speed': 0.0,
                            'error': f"{err.message}"
                        })
                        finished = True

            # Cleanup
            self.pipeline.set_state(Gst.State.NULL)

        except Exception as e:
            elapsed = time.time() - self.start_time if self.start_time else 0
            self.results_queue.put({
                'stream_id': self.stream_id,
                'success': False,
                'elapsed': elapsed,
                'speed': 0.0,
                'error': str(e)
            })


def test_parallel_streams(num_streams, duration=20):
    """Test N parallel streams"""
    print(f"\nTesting {num_streams} parallel streams ({duration}s each)...")

    threads = []
    results_queue = Queue()

    # Start all streams
    start_time = time.time()
    for i in range(num_streams):
        encoder = StreamEncoder(i + 1, duration, results_queue)
        thread = threading.Thread(target=encoder.run)
        thread.start()
        threads.append(thread)
        time.sleep(0.05)  # Small delay between starts

    # Wait for all to complete
    for thread in threads:
        thread.join()

    total_time = time.time() - start_time

    # Collect results
    results = []
    while not results_queue.empty():
        results.append(results_queue.get())

    results.sort(key=lambda x: x['stream_id'])

    # Analyze
    successful = [r for r in results if r['success']]
    failed = [r for r in results if not r['success']]

    # With is-live=true, speed is always ~1.0x, so we measure by completion
    # Expected time should be close to duration (allowing +10% overhead)
    expected_time = duration * 1.1
    all_completed_on_time = total_time <= expected_time

    if successful:
        avg_elapsed = sum(r['elapsed'] for r in successful) / len(successful)
        min_elapsed = min(r['elapsed'] for r in successful)
        max_elapsed = max(r['elapsed'] for r in successful)
    else:
        avg_elapsed = min_elapsed = max_elapsed = 0.0

    print(f"  Total time: {total_time:.2f}s (expected: ~{duration}s)")
    print(f"  Successful: {len(successful)}/{num_streams}")
    print(f"  Failed: {len(failed)}/{num_streams}")

    if successful:
        print(f"  Avg elapsed: {avg_elapsed:.2f}s")
        print(f"  Min elapsed: {min_elapsed:.2f}s")
        print(f"  Max elapsed: {max_elapsed:.2f}s")

    if failed:
        print(f"  Failed streams: {[r['stream_id'] for r in failed]}")
        # Show first error
        if failed[0]['error']:
            print(f"  First error: {failed[0]['error'][:100]}")

    # Success: all streams completed without errors and on time
    all_success = (len(successful) == num_streams) and all_completed_on_time

    return {
        'num_streams': num_streams,
        'successful': len(successful),
        'failed': len(failed),
        'avg_elapsed': avg_elapsed,
        'max_elapsed': max_elapsed,
        'all_success': all_success,
        'total_time': total_time
    }


def main():
    """Find maximum parallel NVENC streams"""
    print("="*70)
    print("GStreamer NVENC Parallel Encoding Capacity Test")
    print("="*70)

    # Test different stream counts
    test_counts = [1, 2, 4, 8, 12, 16, 20, 24, 28, 32]
    duration = 20  # 20 seconds per test for accurate measurement

    results = []
    max_realtime_streams = 0

    for count in test_counts:
        result = test_parallel_streams(count, duration)
        results.append(result)

        if result['all_success'] and result['successful'] == count:
            max_realtime_streams = count
            print(f"  ✓ All streams completed successfully")
        else:
            print(f"  ✗ Some streams failed or took too long")
            if result['failed'] > 0:
                break  # Stop if streams are failing

        time.sleep(2)  # Cool down between tests

    # Summary
    print("\n" + "="*70)
    print("Summary")
    print("="*70)
    print(f"Maximum concurrent streams: {max_realtime_streams}")
    print(f"Test duration: {duration}s per stream")

    print("\nDetailed Results:")
    print(f"{'Streams':<10} {'Success':<12} {'Avg Time':<12} {'Max Time':<12} {'Status':<10}")
    print("-" * 70)
    for r in results:
        status = "✓ PASS" if r['all_success'] else "✗ FAIL"
        print(f"{r['num_streams']:<10} {r['successful']}/{r['num_streams']:<10} "
              f"{r['avg_elapsed']:>6.2f}s      {r['max_elapsed']:>6.2f}s      {status}")

    print("="*70)
    return max_realtime_streams > 0


if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)
