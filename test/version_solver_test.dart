// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/lock_file.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/source_registry.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  group('basic graph', basicGraph);
  group('with lockfile', withLockFile);
  group('root dependency', rootDependency);
  group('dev dependency', devDependency);
  group('unsolvable', unsolvable);
  group('bad source', badSource);
  group('backtracking', backtracking);
  group('Dart SDK constraint', dartSdkConstraint);
  group('Flutter SDK constraint', flutterSdkConstraint);
  group('pre-release', prerelease);
  group('override', override);
  group('downgrade', downgrade);
}

void basicGraph() {
  integration('no dependencies', () {
    d.appDir().create();
    expectResolves(result: {});
  });

  integration('simple dependency tree', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'aa': '1.0.0', 'ab': '1.0.0'});
      builder.serve('aa', '1.0.0');
      builder.serve('ab', '1.0.0');
      builder.serve('b', '1.0.0', deps: {'ba': '1.0.0', 'bb': '1.0.0'});
      builder.serve('ba', '1.0.0');
      builder.serve('bb', '1.0.0');
    });

    d.appDir({'a': '1.0.0', 'b': '1.0.0'}).create();
    expectResolves(result: {
      'a': '1.0.0',
      'aa': '1.0.0',
      'ab': '1.0.0',
      'b': '1.0.0',
      'ba': '1.0.0',
      'bb': '1.0.0'
    });
  });

  integration('shared dependency with overlapping constraints', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'shared': '>=2.0.0 <4.0.0'});
      builder.serve('b', '1.0.0', deps: {'shared': '>=3.0.0 <5.0.0'});
      builder.serve('shared', '2.0.0');
      builder.serve('shared', '3.0.0');
      builder.serve('shared', '3.6.9');
      builder.serve('shared', '4.0.0');
      builder.serve('shared', '5.0.0');
    });

    d.appDir({'a': '1.0.0', 'b': '1.0.0'}).create();
    expectResolves(result: {'a': '1.0.0', 'b': '1.0.0', 'shared': '3.6.9'});
  });

  integration('shared dependency where dependent version in turn affects other '
      'dependencies', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '1.0.1', deps: {'bang': '1.0.0'});
      builder.serve('foo', '1.0.2', deps: {'whoop': '1.0.0'});
      builder.serve('foo', '1.0.3', deps: {'zoop': '1.0.0'});
      builder.serve('bar', '1.0.0', deps: {'foo': '<=1.0.1'});
      builder.serve('bang', '1.0.0');
      builder.serve('whoop', '1.0.0');
      builder.serve('zoop', '1.0.0');
    });

    d.appDir({'foo': '<=1.0.2', 'bar': '1.0.0'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.0', 'bang': '1.0.0'});
  });

  integration('circular dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('bar', '1.0.0', deps: {'foo': '1.0.0'});
    });

    d.appDir({'foo': '1.0.0'}).create();
    expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  integration('removed dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '2.0.0', deps: {'baz': '1.0.0'});
      builder.serve('baz', '1.0.0', deps: {'foo': '2.0.0'});
    });

    d.appDir({'foo': '1.0.0', 'bar': 'any'}).create();
    expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'}, tries: 2);
  });
}

void withLockFile() {
  integration('with compatible locked dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.0.1', deps: {'bar': '1.0.1'});
      builder.serve('foo', '1.0.2', deps: {'bar': '1.0.2'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.0.1');
      builder.serve('bar', '1.0.2');
    });

    d.appDir({'foo': '1.0.1'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});
  });

  integration('with incompatible locked dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.0.1', deps: {'bar': '1.0.1'});
      builder.serve('foo', '1.0.2', deps: {'bar': '1.0.2'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.0.1');
      builder.serve('bar', '1.0.2'); 
    });

    d.appDir({'foo': '1.0.1'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    d.appDir({'foo': '>1.0.1'}).create();
    expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  integration('with unrelated locked dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.0.1', deps: {'bar': '1.0.1'});
      builder.serve('foo', '1.0.2', deps: {'bar': '1.0.2'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.0.1');
      builder.serve('bar', '1.0.2');
      builder.serve('baz', '1.0.0');
    });

    d.appDir({'baz': '1.0.0'}).create();
    expectResolves(result: {'baz': '1.0.0'});

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  integration('unlocks dependencies if necessary to ensure that a new '
      'dependency is satisfied', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '<2.0.0'});
      builder.serve('bar', '1.0.0', deps: {'baz': '<2.0.0'});
      builder.serve('baz', '1.0.0', deps: {'qux': '<2.0.0'});
      builder.serve('qux', '1.0.0');
      builder.serve('foo', '2.0.0', deps: {'bar': '<3.0.0'});
      builder.serve('bar', '2.0.0', deps: {'baz': '<3.0.0'});
      builder.serve('baz', '2.0.0', deps: {'qux': '<3.0.0'});
      builder.serve('qux', '2.0.0');
      builder.serve('newdep', '2.0.0', deps: {'baz': '>=1.5.0'});
    });

    d.appDir({'foo': '1.0.0'}).create();
    expectResolves(result: {
      'foo': '1.0.0',
      'bar': '1.0.0',
      'baz': '1.0.0',
      'qux': '1.0.0'
    });

    d.appDir({'foo': 'any', 'newdep': '2.0.0'}).create();
    expectResolves(result: {
      'foo': '2.0.0',
      'bar': '2.0.0',
      'baz': '2.0.0',
      'qux': '1.0.0',
      'newdep': '2.0.0'
    }, tries: 4);
  });
}

void rootDependency() {
  integration('with root source', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'myapp': 'any'});
    });

    d.appDir({'foo': '1.0.0'}).create();
    expectResolves(result: {'foo': '1.0.0'});
  });

  integration('with mismatched sources', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'myapp': 'any'});
      builder.serve('bar', '1.0.0', deps: {'myapp': {'git': 'nowhere'}});
    });

    d.appDir({'foo': '1.0.0', 'bar': '1.0.0'}).create();
    expectResolves(
        error: "Incompatible dependencies on myapp:\n"
               "- bar 1.0.0 depends on it from source git\n"
               "- foo 1.0.0 depends on it from source hosted");
  });

  integration('with wrong version', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'myapp': '>0.0.0'});
    });

    d.appDir({'foo': '1.0.0'}).create();
    expectResolves(
        error: "Package myapp has no versions that match >0.0.0 derived from:\n"
               "- foo 1.0.0 depends on version >0.0.0");
  });
}

void devDependency() {
  integration("includes root package's dev dependencies", () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('bar', '1.0.0'); 
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {
          'foo': '1.0.0',
          'bar': '1.0.0'
        }
      })
    ]).create();

    expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  integration("includes dev dependency's transitive dependencies", () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('bar', '1.0.0');
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.0.0'}
      })
    ]).create();
    
    expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  integration("ignores transitive dependency's dev dependencies", () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'dev_dependencies': {'bar': '1.0.0'}
      });
    });

    d.appDir({'foo': '1.0.0'}).create();
    expectResolves(result: {'foo': '1.0.0'});
  });
}

void unsolvable() {
  integration('no version that matches constraint', () {
    servePackages((builder) {
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '2.1.3');
    });

    d.appDir({'foo': '>=1.0.0 <2.0.0'}).create();
    expectResolves(
        error: 'Package foo has no versions that match >=1.0.0 <2.0.0 derived '
                 'from:\n'
               '- myapp depends on version >=1.0.0 <2.0.0');
  });

  integration('no version that matches combined constraint', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'shared': '>=2.0.0 <3.0.0'});
      builder.serve('bar', '1.0.0', deps: {'shared': '>=2.9.0 <4.0.0'});
      builder.serve('shared', '2.5.0');
      builder.serve('shared', '3.5.0'); 
    });

    d.appDir({'foo': '1.0.0', 'bar': '1.0.0'}).create();
    expectResolves(
        error: 'Package shared has no versions that match >=2.9.0 <3.0.0 '
                 'derived from:\n'
               '- bar 1.0.0 depends on version >=2.9.0 <4.0.0\n'
               '- foo 1.0.0 depends on version >=2.0.0 <3.0.0');
  });

  integration('disjoint constraints', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'shared': '<=2.0.0'});
      builder.serve('bar', '1.0.0', deps: {'shared': '>3.0.0'});
      builder.serve('shared', '2.0.0');
      builder.serve('shared', '4.0.0'); 
    });

    d.appDir({'foo': '1.0.0', 'bar': '1.0.0'}).create();
    expectResolves(
        error: 'Incompatible version constraints on shared:\n'
               '- bar 1.0.0 depends on version >3.0.0\n'
               '- foo 1.0.0 depends on version <=2.0.0');
  });

  integration('mismatched descriptions', () {
    var otherServer = new PackageServer((builder) {
      builder.serve('shared', '1.0.0');
    });

    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'shared': '1.0.0'});
      builder.serve('bar', '1.0.0', deps: {
        'shared': {
          'hosted': {'name': 'shared', 'url': otherServer.url},
          'version': '1.0.0'
        }
      });
      builder.serve('shared', '1.0.0');
    });

    d.appDir({'foo': '1.0.0', 'bar': '1.0.0'}).create();
    expectResolves(error: allOf([
      contains('Incompatible dependencies on shared:'),
      contains('- bar 1.0.0 depends on it with description'),
      contains('- foo 1.0.0 depends on it with description "shared"')
    ]));
  });

  integration('mismatched sources', () {
    d.dir('shared', [d.libPubspec('shared', '1.0.0')]).create();

    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'shared': '1.0.0'});
      builder.serve('bar', '1.0.0', deps: {
        'shared': {'path': p.join(sandboxDir, 'shared')}
      });
      builder.serve('shared', '1.0.0');
    });

    d.appDir({'foo': '1.0.0', 'bar': '1.0.0'}).create();
    expectResolves(
        error: 'Incompatible dependencies on shared:\n'
               '- bar 1.0.0 depends on it from source path\n'
               '- foo 1.0.0 depends on it from source hosted');
  });

  integration('no valid solution', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'b': '1.0.0'});
      builder.serve('a', '2.0.0', deps: {'b': '2.0.0'});
      builder.serve('b', '1.0.0', deps: {'a': '2.0.0'});
      builder.serve('b', '2.0.0', deps: {'a': '1.0.0'});
    });

    d.appDir({'a': 'any', 'b': 'any'}).create();
    expectResolves(
        error: 'Package a has no versions that match 2.0.0 derived from:\n'
               '- b 1.0.0 depends on version 2.0.0\n'
               '- myapp depends on version any',
        tries: 2);
  });

  // This is a regression test for #15550.
  integration('no version that matches while backtracking', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0');
    });

    d.appDir({'a': 'any', 'b': '>1.0.0'}).create();
    expectResolves(
        error: 'Package b has no versions that match >1.0.0 derived from:\n'
               '- myapp depends on version >1.0.0');
  });

  // This is a regression test for #18300.
  integration('issue 18300', () {
    servePackages((builder) {
      builder.serve('analyzer', '0.12.2');
      builder.serve('angular', '0.10.0', deps: {
        'di': '>=0.0.32 <0.1.0',
        'collection': '>=0.9.1 <1.0.0'
      });
      builder.serve('angular', '0.9.11', deps: {
        'di': '>=0.0.32 <0.1.0',
        'collection': '>=0.9.1 <1.0.0'
      });
      builder.serve('angular', '0.9.10', deps: {
        'di': '>=0.0.32 <0.1.0',
        'collection': '>=0.9.1 <1.0.0'
      });
      builder.serve('collection', '0.9.0');
      builder.serve('collection', '0.9.1');
      builder.serve('di', '0.0.37', deps: {'analyzer': '>=0.13.0 <0.14.0'});
      builder.serve('di', '0.0.36', deps: {'analyzer': '>=0.13.0 <0.14.0'}); 
    });

    d.appDir({'angular': 'any', 'collection': 'any'}).create();
    expectResolves(
        error: 'Package analyzer has no versions that match >=0.13.0 <0.14.0 '
                 'derived from:\n'
               '- di 0.0.36 depends on version >=0.13.0 <0.14.0',
        tries: 2);
  });
}

void badSource() {
  integration('fail if the root package has a bad source in dep', () {
    d.appDir({'foo': {'bad': 'any'}}).create();
    expectResolves(
        error: 'Package myapp depends on foo from unknown source "bad".');
  });

  integration('fail if the root package has a bad source in dev dep', () {
    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': {'bad': 'any'}}
      })
    ]).create();

    expectResolves(
        error: 'Package myapp depends on foo from unknown source "bad".');
  });

  integration('fail if all versions have bad source in dep', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': {'bad': 'any'}});
      builder.serve('foo', '1.0.1', deps: {'baz': {'bad': 'any'}});
      builder.serve('foo', '1.0.2', deps: {'bang': {'bad': 'any'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(
        error: 'Package foo depends on bar from unknown source "bad".');
  });

  integration('ignore versions with bad source in dep', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': 'any'});
      builder.serve('foo', '1.0.1', deps: {'bar': {'bad': 'any'}});
      builder.serve('foo', '1.0.2', deps: {'bar': {'bad': 'any'}});
      builder.serve('bar', '1.0.0');
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });
}

void backtracking() {
  integration('circular dependency on older version', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '2.0.0', deps: {'b': '1.0.0'});
      builder.serve('b', '1.0.0', deps: {'a': '1.0.0'});
    });

    d.appDir({'a': '>=1.0.0'}).create();
    expectResolves(result: {'a': '1.0.0'}, tries: 2);
  });

  // The latest versions of a and b disagree on c. An older version of either
  // will resolve the problem. This test validates that b, which is farther
  // in the dependency graph from myapp is downgraded first.
  integration('rolls back leaf versions first', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'b': 'any'});
      builder.serve('a', '2.0.0', deps: {'b': 'any', 'c': '2.0.0'});
      builder.serve('b', '1.0.0');
      builder.serve('b', '2.0.0', deps: {'c': '1.0.0'});
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
    });

    d.appDir({'a': 'any'}).create();
    expectResolves(
        result: {'a': '2.0.0', 'b': '1.0.0', 'c': '2.0.0'});
  });

  // Only one version of baz, so foo and bar will have to downgrade until they
  // reach it.
  integration('simple transitive', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '2.0.0', deps: {'bar': '2.0.0'});
      builder.serve('foo', '3.0.0', deps: {'bar': '3.0.0'});
      builder.serve('bar', '1.0.0', deps: {'baz': 'any'});
      builder.serve('bar', '2.0.0', deps: {'baz': '2.0.0'});
      builder.serve('bar', '3.0.0', deps: {'baz': '3.0.0'});
      builder.serve('baz', '1.0.0');
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(
        result: {'foo': '1.0.0', 'bar': '1.0.0', 'baz': '1.0.0'},
        tries: 3);
  });

  // This ensures it doesn't exhaustively search all versions of b when it's
  // a-2.0.0 whose dependency on c-2.0.0-nonexistent led to the problem. We
  // make sure b has more versions than a so that the solver tries a first
  // since it sorts sibling dependencies by number of versions.
  integration('backjump to nearer unsatisfied package', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'c': '1.0.0'});
      builder.serve('a', '2.0.0', deps: {'c': '2.0.0-nonexistent'});
      builder.serve('b', '1.0.0');
      builder.serve('b', '2.0.0');
      builder.serve('b', '3.0.0');
      builder.serve('c', '1.0.0');
    });

    d.appDir({'a': 'any', 'b': 'any'}).create();
    expectResolves(
        result: {'a': '1.0.0', 'b': '3.0.0', 'c': '1.0.0'},
        tries: 2);
  });

  // Tests that the backjumper will jump past unrelated selections when a
  // source conflict occurs. This test selects, in order:
  // - myapp -> a
  // - myapp -> b
  // - myapp -> c (1 of 5)
  // - b -> a
  // It selects a and b first because they have fewer versions than c. It
  // traverses b's dependency on a after selecting a version of c because
  // dependencies are traversed breadth-first (all of myapps's immediate deps
  // before any other their deps).
  //
  // This means it doesn't discover the source conflict until after selecting
  // c. When that happens, it should backjump past c instead of trying older
  // versions of it since they aren't related to the conflict.
  integration('successful backjump to conflicting source', () {
    d.dir('a', [d.libPubspec('a', '1.0.0')]).create();

    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0', deps: {'a': 'any'});
      builder.serve('b', '2.0.0', deps: {
        'a': {'path': p.join(sandboxDir, 'a')}
      });
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
      builder.serve('c', '3.0.0');
      builder.serve('c', '4.0.0');
      builder.serve('c', '5.0.0');
    });

    d.appDir({'a': 'any', 'b': 'any', 'c': 'any'}).create();
    expectResolves(result: {'a': '1.0.0', 'b': '1.0.0', 'c': '5.0.0'});
  });

  // Like the above test, but for a conflicting description.
  integration('successful backjump to conflicting description', () {
    var otherServer = new PackageServer((builder) {
      builder.serve('a', '1.0.0');
    });

    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0', deps: {'a': 'any'});
      builder.serve('b', '2.0.0', deps: {
        'a': {'hosted': {'name': 'a', 'url': otherServer.url}}
      });
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
      builder.serve('c', '3.0.0');
      builder.serve('c', '4.0.0');
      builder.serve('c', '5.0.0');
    });

    d.appDir({'a': 'any', 'b': 'any', 'c': 'any'}).create();
    expectResolves(result: {'a': '1.0.0', 'b': '1.0.0', 'c': '5.0.0'});
  });

  // Similar to the above two tests but where there is no solution. It should
  // fail in this case with no backtracking.
  integration('failing backjump to conflicting source', () {
    d.dir('a', [d.libPubspec('a', '1.0.0')]).create();

    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0', deps: {
        'a': {'path': p.join(sandboxDir, 'shared')}
      });
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
      builder.serve('c', '3.0.0');
      builder.serve('c', '4.0.0');
      builder.serve('c', '5.0.0'); 
    });

    d.appDir({'a': 'any', 'b': 'any', 'c': 'any'}).create();
    expectResolves(
        error: 'Incompatible dependencies on a:\n'
               '- b 1.0.0 depends on it from source path\n'
               '- myapp depends on it from source hosted');
  });

  integration('failing backjump to conflicting description', () {
    var otherServer = new PackageServer((builder) {
      builder.serve('a', '1.0.0');
    });

    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0', deps: {
        'a': {'hosted': {'name': 'a', 'url': otherServer.url}}
      });
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
      builder.serve('c', '3.0.0');
      builder.serve('c', '4.0.0');
      builder.serve('c', '5.0.0');
    });

    d.appDir({'a': 'any', 'b': 'any', 'c': 'any'}).create();
    expectResolves(error: allOf([
      contains('Incompatible dependencies on a:'),
      contains('- b 1.0.0 depends on it with description'),
      contains('- myapp depends on it with description "a"')
    ]));
  });

  // Dependencies are ordered so that packages with fewer versions are tried
  // first. Here, there are two valid solutions (either a or b must be
  // downgraded once). The chosen one depends on which dep is traversed first.
  // Since b has fewer versions, it will be traversed first, which means a will
  // come later. Since later selections are revised first, a gets downgraded.
  integration('traverse into package with fewer versions first', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'c': 'any'});
      builder.serve('a', '2.0.0', deps: {'c': 'any'});
      builder.serve('a', '3.0.0', deps: {'c': 'any'});
      builder.serve('a', '4.0.0', deps: {'c': 'any'});
      builder.serve('a', '5.0.0', deps: {'c': '1.0.0'});
      builder.serve('b', '1.0.0', deps: {'c': 'any'});
      builder.serve('b', '2.0.0', deps: {'c': 'any'});
      builder.serve('b', '3.0.0', deps: {'c': 'any'});
      builder.serve('b', '4.0.0', deps: {'c': '2.0.0'});
      builder.serve('c', '1.0.0');
      builder.serve('c', '2.0.0');
    });

    d.appDir({'a': 'any', 'b': 'any'}).create();
    expectResolves(result: {'a': '4.0.0', 'b': '4.0.0', 'c': '2.0.0'});
  });

  // This is similar to the above test. When getting the number of versions of
  // a package to determine which to traverse first, versions that are
  // disallowed by the root package's constraints should not be considered.
  // Here, foo has more versions of bar in total (4), but fewer that meet
  // myapp's constraints (only 2). There is no solution, but we will do less
  // backtracking if foo is tested first.
  integration('take root package constraints into counting versions', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'none': '2.0.0'});
      builder.serve('foo', '2.0.0', deps: {'none': '2.0.0'});
      builder.serve('foo', '3.0.0', deps: {'none': '2.0.0'});
      builder.serve('foo', '4.0.0', deps: {'none': '2.0.0'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '2.0.0');
      builder.serve('bar', '3.0.0');
      builder.serve('none', '1.0.0'); 
    });

    d.appDir({"foo": ">2.0.0", "bar": "any"}).create();
    expectResolves(
        error: 'Package none has no versions that match 2.0.0 derived from:\n'
               '- foo 3.0.0 depends on version 2.0.0',
        tries: 2);
  });

  integration('complex backtrack', () {
    servePackages((builder) {
      // This sets up a hundred versions of foo and bar, 0.0.0 through 9.9.0. Each
      // version of foo depends on a baz with the same major version. Each version
      // of bar depends on a baz with the same minor version. There is only one
      // version of baz, 0.0.0, so only older versions of foo and bar will
      // satisfy it.
      builder.serve('baz', '0.0.0');
      for (var i = 0; i < 10; i++) {
        for (var j = 0; j < 10; j++) {
          builder.serve('foo', '$i.$j.0', deps: {'baz': '$i.0.0'});
          builder.serve('bar', '$i.$j.0', deps: {'baz': '0.$j.0'});
        }
      }
    });

    d.appDir({'foo': 'any', 'bar': 'any'}).create();
    expectResolves(
        result: {'foo': '0.9.0', 'bar': '9.0.0', 'baz': '0.0.0'},
        tries: 10);
  });

  // If there's a disjoint constraint on a package, then selecting other
  // versions of it is a waste of time: no possible versions can match. We need
  // to jump past it to the most recent package that affected the constraint.
  integration('backjump past failed package on disjoint constraint', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {
        'foo': 'any' // ok
      });
      builder.serve('a', '2.0.0', deps: {
        'foo': '<1.0.0' // disjoint with myapp's constraint on foo
      });
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '2.0.1');
      builder.serve('foo', '2.0.2');
      builder.serve('foo', '2.0.3');
      builder.serve('foo', '2.0.4');      
    });

    d.appDir({'a': 'any', 'foo': '>2.0.0'}).create();
    expectResolves(result: {'a': '1.0.0', 'foo': '2.0.4'});
  });

  // This is a regression test for #18666. It was possible for the solver to
  // "forget" that a package had previously led to an error. In that case, it
  // would backtrack over the failed package instead of trying different
  // versions of it.
  integration("finds solution with less strict constraint", () {
    servePackages((builder) {
      builder.serve('a', '2.0.0');
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0', deps: {'a': '1.0.0'});
      builder.serve('c', '1.0.0', deps: {'b': 'any'});
      builder.serve('d', '2.0.0', deps: {'myapp': 'any'});
      builder.serve('d', '1.0.0', deps: {'myapp': '<1.0.0'}); 
    });

    d.appDir({"a": "any", "c": "any", "d": "any"}).create();
    expectResolves(
        result: {'a': '1.0.0', 'b': '1.0.0', 'c': '1.0.0', 'd': '2.0.0'});
  });
}

void dartSdkConstraint() {
  integration('root matches SDK', () {
    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '0.1.2+3'}
      })
    ]).create();

    expectResolves(result: {});
  });

  integration('root does not match SDK', () {
    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '0.0.0'}
      })
    ]).create();

    expectResolves(error: 'Package myapp requires SDK version 0.0.0 but the '
                 'current SDK is 0.1.2+3.');
  });

  integration('dependency does not match SDK', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(
        error: 'Package foo requires SDK version 0.0.0 but the '
                 'current SDK is 0.1.2+3.');
  });

  integration('transitive dependency does not match SDK', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': 'any'});
      builder.serve('bar', '1.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(
        error: 'Package bar requires SDK version 0.0.0 but the '
                 'current SDK is 0.1.2+3.');
  });

  integration('selects a dependency version that allows the SDK', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('foo', '2.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('foo', '3.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
      builder.serve('foo', '4.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '2.0.0'});
  });

  integration('selects a transitive dependency version that allows the SDK',
      () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': 'any'});
      builder.serve('bar', '1.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('bar', '2.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('bar', '3.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
      builder.serve('bar', '4.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '1.0.0', 'bar': '2.0.0'});
  });

  integration('selects a dependency version that allows a transitive '
      'dependency that allows the SDK', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '2.0.0', deps: {'bar': '2.0.0'});
      builder.serve('foo', '3.0.0', deps: {'bar': '3.0.0'});
      builder.serve('foo', '4.0.0', deps: {'bar': '4.0.0'});
      builder.serve('bar', '1.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('bar', '2.0.0',
          pubspec: {'environment': {'sdk': '0.1.2+3'}});
      builder.serve('bar', '3.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
      builder.serve('bar', '4.0.0', pubspec: {'environment': {'sdk': '0.0.0'}});
    });

    d.appDir({'foo': 'any'}).create();
    expectResolves(result: {'foo': '2.0.0', 'bar': '2.0.0'}, tries: 3);
  });
}

void flutterSdkConstraint() {
  group('without a Flutter SDK', () {
    integration('fails for the root package', () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': '1.2.3'}
        })
      ]).create();

      expectResolves(
          error: 'Package myapp requires the Flutter SDK, which is not '
                    'available.');
    });

    integration('fails for a dependency', () {
      servePackages((builder) {
        builder.serve('foo', '1.0.0',
            pubspec: {'environment': {'flutter': '0.0.0'}});
      });

      d.appDir({'foo': 'any'}).create();
      expectResolves(
          error: 'Package foo requires the Flutter SDK, which is not '
                    'available.');
    });

    integration("chooses a version that doesn't need Flutter", () {
      servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0');
        builder.serve('foo', '3.0.0',
            pubspec: {'environment': {'flutter': '0.0.0'}});
      });

      d.appDir({'foo': 'any'}).create();
      expectResolves(result: {'foo': '2.0.0'});
    });

    integration('fails even with a matching Dart SDK constraint', () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {
            'dart': '0.1.2+3',
            'flutter': '1.2.3'
          }
        })
      ]).create();

      expectResolves(
          error: 'Package myapp requires the Flutter SDK, which is not '
                    'available.');
    });
  });

  group('with a Flutter SDK', () {
    setUp(() {
      d.dir('flutter', [
        d.file('version', '1.2.3')
      ]).create();
    });

    integration('succeeds with a matching constraint', () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': 'any'}
        })
      ]).create();

      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          result: {});
    });

    integration('fails with a non-matching constraint', () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': '>1.2.3'}
        })
      ]).create();

      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          error: 'Package myapp requires Flutter SDK version >1.2.3 but the '
                    'current SDK is 1.2.3.');
    });

    integration('succeeds if both Flutter and Dart SDKs match', () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {
            'sdk': '0.1.2+3',
            'flutter': '1.2.3'
          }
        })
      ]).create();

      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          result: {});
    });

    integration("fails if Flutter SDK doesn't match but Dart does", () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {
            'sdk': '0.1.2+3',
            'flutter': '>1.2.3'
          }
        })
      ]).create();

      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          error: 'Package myapp requires Flutter SDK version >1.2.3 but the '
                    'current SDK is 1.2.3.');
    });

    integration("fails if Dart SDK doesn't match but Flutter does", () {
      d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {
            'sdk': '>0.1.2+3',
            'flutter': '1.2.3'
          }
        })
      ]).create();

      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          error: 'Package myapp requires SDK version >0.1.2+3 but the current '
                   'SDK is 0.1.2+3.');
    });

    integration('selects the latest dependency with a matching constraint', () {
      servePackages((builder) {
        builder.serve('foo', '1.0.0',
            pubspec: {'environment': {'flutter': '^0.0.0'}});
        builder.serve('foo', '2.0.0',
            pubspec: {'environment': {'flutter': '^1.0.0'}});
        builder.serve('foo', '3.0.0',
            pubspec: {'environment': {'flutter': '^2.0.0'}});
      });

      d.appDir({'foo': 'any'}).create();
      expectResolves(
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
          result: {'foo': '2.0.0'});
    });
  });
}

void prerelease() {
  integration('prefer stable versions over unstable', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '1.1.0-dev');
      builder.serve('a', '2.0.0-dev');
      builder.serve('a', '3.0.0-dev');
    });

    d.appDir({'a': 'any'}).create();
    expectResolves(result: {'a': '1.0.0'});
  });

  integration('use latest allowed prerelease if no stable versions match', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0-dev');
      builder.serve('a', '1.1.0-dev');
      builder.serve('a', '1.9.0-dev');
      builder.serve('a', '3.0.0');
    });

    d.appDir({'a': '<2.0.0'}).create();
    expectResolves(result: {'a': '1.9.0-dev'});
  });

  integration('use an earlier stable version on a < constraint', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '1.1.0');
      builder.serve('a', '2.0.0-dev');
      builder.serve('a', '2.0.0'); 
    });

    d.appDir({'a': '<2.0.0'}).create();
    expectResolves(result: {'a': '1.1.0'});
  });

  integration('prefer a stable version even if constraint mentions unstable',
      () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '1.1.0');
      builder.serve('a', '2.0.0-dev');
      builder.serve('a', '2.0.0');
    });

    d.appDir({'a': '<=2.0.0-dev'}).create();
    expectResolves(result: {'a': '1.1.0'});
  });
}

void override() {
  integration('chooses best version matching override constraint', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '2.0.0');
      builder.serve('a', '3.0.0');
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'a': 'any'},
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    expectResolves(result: {'a': '2.0.0'});
  });

  integration('uses override as dependency', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '2.0.0');
      builder.serve('a', '3.0.0');
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    expectResolves(result: {'a': '2.0.0'});
  });

  integration('ignores other constraints on overridden package', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '2.0.0');
      builder.serve('a', '3.0.0');
      builder.serve('b', '1.0.0', deps: {'a': '1.0.0'});
      builder.serve('c', '1.0.0', deps: {'a': '3.0.0'}); 
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'b': 'any', 'c': 'any'},
        'dependency_overrides': {'a': '2.0.0'}
      })
    ]).create();

    expectResolves(result: {'a': '2.0.0', 'b': '1.0.0', 'c': '1.0.0'});
  });

  integration('backtracks on overidden package for its constraints', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0', deps: {'shared': 'any'});
      builder.serve('a', '2.0.0', deps: {'shared': '1.0.0'});
      builder.serve('shared', '1.0.0');
      builder.serve('shared', '2.0.0'); 
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'shared': '2.0.0'},
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    expectResolves(result: {'a': '1.0.0', 'shared': '2.0.0'});
  });

  integration('override compatible with locked dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.0.1', deps: {'bar': '1.0.1'});
      builder.serve('foo', '1.0.2', deps: {'bar': '1.0.2'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.0.1');
      builder.serve('bar', '1.0.2'); 
    });

    d.appDir({'foo': '1.0.1'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '<1.0.2'}
      })
    ]).create();
    
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});
  });

  integration('override incompatible with locked dependency', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.0.1', deps: {'bar': '1.0.1'});
      builder.serve('foo', '1.0.2', deps: {'bar': '1.0.2'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.0.1');
      builder.serve('bar', '1.0.2'); 
    });

    d.appDir({'foo': '1.0.1'}).create();
    expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '>1.0.1'}
      })
    ]).create();
    
    expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  integration('no version that matches override', () {
    servePackages((builder) {
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '2.1.3');
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '>=1.0.0 <2.0.0'}
      })
    ]).create();

    expectResolves(
        error: 'Package foo has no versions that match >=1.0.0 <2.0.0 derived '
                 'from:\n'
               '- myapp depends on version >=1.0.0 <2.0.0');
  });

  integration('overrides a bad source without error', () {
    servePackages((builder) {
      builder.serve('foo', '0.0.0');
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': {'bad': 'any'}},
        'dependency_overrides': {'foo': 'any'}
      })
    ]).create();

    expectResolves(result: {'foo': '0.0.0'});
  });

  integration('overrides an unmatched root dependency', () {
    servePackages((builder) {
      builder.serve('foo', '0.0.0', deps: {'myapp': '1.0.0'});
    });

    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '2.0.0',
        'dependency_overrides': {'foo': 'any'}
      })
    ]).create();

    expectResolves(result: {'foo': '0.0.0'});
  });
}

void downgrade() {
  integration("downgrades a dependency to the lowest matching version", () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0-dev');
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '2.1.0');
    });

    d.appDir({'foo': '2.1.0'}).create();
    expectResolves(result: {'foo': '2.1.0'});

    d.appDir({'foo': '>=2.0.0 <3.0.0'}).create();
    expectResolves(result: {'foo': '2.0.0'}, downgrade: true);
  });

  integration('use earliest allowed prerelease if no stable versions match '
      'while downgrading', () {
    servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('a', '2.0.0-dev.1');
      builder.serve('a', '2.0.0-dev.2');
      builder.serve('a', '2.0.0-dev.3');
    });

    d.appDir({'a': '>=2.0.0-dev.1 <3.0.0'}).create();
    expectResolves(result: {'a': '2.0.0-dev.1'}, downgrade: true);
  });
}

/// Runs "pub get" and makes assertions about its results.
///
/// If [result] is passed, it's parsed as a pubspec-style dependency map, and
/// this asserts that the resulting lockfile matches those dependencies, and
/// that it contains only packages listed in [result].
///
/// If [error] is passed, this asserts that pub's error output matches the
/// value. It may be a String, a [RegExp], or a [Matcher].
///
/// Asserts that version solving looks at exactly [tries] solutions. It defaults
/// to allowing only a single solution.
///
/// If [environment] is passed, it's added to the OS environment when running
/// pub.
///
/// If [downgrade] is `true`, this runs "pub downgrade" instead of "pub get".
void expectResolves({Map result, error, int tries,
    Map<String, String> environment, bool downgrade: false}) {
  schedulePub(
      args: [downgrade ? 'downgrade' : 'get'],
      environment: environment,
      output: error == null
          ? anyOf(
              contains('Got dependencies!'),
              matches(new RegExp(r'Changed \d+ dependenc(ies|y)!')))
          : null,
      error: error,
      silent: contains('Tried ${tries ?? 1} solutions'),
      exitCode: error == null ? 0 : 1);

  if (result == null) return;

  schedule(() async {
    var registry = new SourceRegistry();
    var lockFile = new LockFile.load(
        p.join(sandboxDir, appPath, 'pubspec.lock'),
        registry);
    var resultPubspec = new Pubspec.fromMap({"dependencies": result}, registry);

    var ids = new Map.from(lockFile.packages);
    for (var dep in resultPubspec.dependencies) {
      expect(ids, contains(dep.name));
      var id = ids.remove(dep.name);

      if (dep.source is HostedSource && dep.description is String) {
        // If the dep uses the default hosted source, grab it from the test
        // package server rather than pub.dartlang.org.
        dep = registry.hosted
            .refFor(dep.name, url: await globalPackageServer.url)
            .withConstraint(dep.constraint);
      }
      expect(dep.allows(id), isTrue, reason: "Expected $id to match $dep.");
    }

    expect(ids, isEmpty, reason: "Expected no additional packages.");
  });
}
