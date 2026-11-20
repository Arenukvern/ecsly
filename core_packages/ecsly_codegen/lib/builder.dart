import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/ecs_component_generator.dart';

Builder ecsComponentBuilder(BuilderOptions options) =>
    PartBuilder([EcsComponentGenerator()], '.ecs.g.dart');
