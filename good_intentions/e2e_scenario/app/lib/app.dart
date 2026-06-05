import 'package:intentions/intentions.dart';
import 'package:shared/shared.dart';

@useCase
class AppUseCase {
  const AppUseCase(this.repository);

  final AppRepository repository;
}

@repository
class AppRepository {
  const AppRepository(this.api);

  final SharedApi api;
}
