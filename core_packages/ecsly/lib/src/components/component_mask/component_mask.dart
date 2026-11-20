import '../component.dart';
import 'component_mask.dart';

export 'component_mask_import.dart';

ComponentMask get emptyComponentMask => ComponentMaskImpl.empty;

ComponentMask createComponentMask(Iterable<ComponentId> ids) =>
    ComponentMaskImpl.fromIds(ids);
