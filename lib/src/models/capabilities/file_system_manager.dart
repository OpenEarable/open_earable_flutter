abstract class FileSystemManager {
  Future<List<FileSystemItem>> listFiles(String directory);
  Future<bool> remove(String path);

  Future<bool> writeFile({required String path, required Stream<List<int>> data});
}

abstract class FileSystemItem {
  final String name;

  FileSystemItem({required this.name});
}

class OWFile extends FileSystemItem {
  OWFile({required super.name});

  @override
  String toString() {
    return 'OWFile(name: $name)';
  }
}

class OWDirectory extends FileSystemItem {
  List<FileSystemItem> items;

  OWDirectory({required super.name, this.items = const []});

  @override
  String toString() {
    return 'OWDirectory(name: $name, items: $items)';
  }
}
