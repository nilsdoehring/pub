// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("fails to load a non-existent transform", () {
    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/transform"]
      })
    ]).create();

    pubGet();
    var pub = startPubServe();
    pub.stderr.expect(
        'Transformer library "package:myapp/transform.dart" not found.');
    pub.shouldExit(1);
  });
}
