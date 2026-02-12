#!/usr/bin/env python3
"""
Test maximum parallel GStreamer NVENC encoding capacity using GI bindings
Uses bus.timed_pop_filtered() pattern from cam_handler (thread-safe, no GLib.MainLoop)
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
            "! nvh264enc rc-mode=vbr preset=1 "
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

    if successful:
        avg_speed = sum(r['speed'] for r in successful) / len(successful)
        min_speed = min(r['speed'] for r in successful)
        max_speed = max(r['speed'] for r in successful)
    else:
        avg_speed = min_speed = max_speed = 0.0

    print(f"  Total time: {total_time:.2f}s")
    print(f"  Successful: {len(successful)}/{num_streams}")
    print(f"  Failed: {len(failed)}/{num_streams}")

    if successful:
        print(f"  Avg speed: {avg_speed:.2f}x")
        print(f"  Min speed: {min_speed:.2f}x")
        print(f"  Max speed: {max_speed:.2f}x")

    if failed:
        print(f"  Failed streams: {[r['stream_id'] for r in failed]}")
        # Show first error
        if failed[0]['error']:
            print(f"  First error: {failed[0]['error'][:100]}")

    # All streams should maintain at least 1x realtime
    all_realtime = all(r['speed'] >= 1.0 for r in successful)

    return {
        'num_streams': num_streams,
        'successful': len(successful),
        'failed': len(failed),
        'avg_speed': avg_speed,
        'min_speed': min_speed,
        'all_realtime': all_realtime,
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

        if result['all_realtime'] and result['successful'] == count:
            max_realtime_streams = count
            print(f"  ✓ All streams maintaining realtime")
        else:
            print(f"  ✗ Not all streams maintaining realtime")
            if result['failed'] > 0:
                break  # Stop if streams are failing

        time.sleep(2)  # Cool down between tests

    # Summary
    print("\n" + "="*70)
    print("Summary")
    print("="*70)
    print(f"Maximum realtime streams: {max_realtime_streams}")

    print("\nDetailed Results:")
    print(f"{'Streams':<10} {'Success':<10} {'Avg Speed':<12} {'Min Speed':<12} {'Status':<10}")
    print("-" * 70)
    for r in results:
        status = "✓ PASS" if r['all_realtime'] else "✗ FAIL"
        print(f"{r['num_streams']:<10} {r['successful']}/{r['num_streams']:<7} "
              f"{r['avg_speed']:>6.2f}x      {r['min_speed']:>6.2f}x      {status}")

    print("="*70)
    return max_realtime_streams > 0


if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)
