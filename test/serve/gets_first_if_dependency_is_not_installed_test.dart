// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("gets first if a dependency is not installed", () {
    servePackages((builder) => builder.serve("foo", "1.2.3"));

    d.appDir({"foo": "1.2.3"}).create();

    // Run pub to get a lock file.
    pubGet();

    // Delete the system cache so it isn't installed any more.
    schedule(() => deleteEntry(path.join(sandboxDir, cachePath)));

    pubGet();
    pubServe();
    requestShouldSucceed("packages/foo/foo.dart", 'main() => "foo 1.2.3";');
    endPubServe();
  });
}
