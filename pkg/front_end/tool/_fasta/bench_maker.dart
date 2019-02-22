// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.tool.entry_points;

import "dart:convert" show JsonEncoder;

import "dart:io" show File;

import "package:kernel/ast.dart" hide MapEntry;

import "package:front_end/src/fasta/type_inference/type_schema.dart"
    show UnknownType;

String jsonEncode(Object object) {
  return const JsonEncoder.withIndent("  ").convert(object);
}

Iterable<String> nameGenerator() sync* {
  int i = 0;
  while (true) {
    List<int> characters = <int>[];
    int j = i;
    while (j > 25) {
      int c = j % 26;
      j = (j ~/ 26) - 1;
      characters.add(c + 65);
    }
    characters.add(j + 65);
    yield new String.fromCharCodes(characters.reversed);
    i++;
  }
}

class BenchMaker implements DartTypeVisitor1<void, StringBuffer> {
  final List<Object> checks = <Object>[];

  final Map<TreeNode, String> nodeNames = <TreeNode, String>{};

  final Set<String> usedNames = new Set<String>();

  final Iterator<String> names = nameGenerator().iterator..moveNext();

  final List<String> classes = <String>[];

  final List<TypeParameter> usedTypeParameters = <TypeParameter>[];

  String serializeTypeChecks(List<Object> typeChecks) {
    for (List<Object> list in typeChecks) {
      writeTypeCheck(list[0], list[1], list[2]);
    }
    writeClasses();
    return jsonEncode(this);
  }

  void writeTypeCheck(DartType s, DartType t, bool expected) {
    assert(usedTypeParameters.isEmpty);
    usedTypeParameters.clear();
    StringBuffer sb = new StringBuffer();
    s.accept1(this, sb);
    String sString = "$sb";
    sb.clear();
    t.accept1(this, sb);
    String tString = "$sb";
    List<Object> arguments = <Object>[sString, tString];
    Set<TypeParameter> seenTypeParameters = new Set<TypeParameter>();
    List<String> parameterStrings = <String>[];
    while (usedTypeParameters.isNotEmpty) {
      List<TypeParameter> typeParameters = usedTypeParameters.toList();
      usedTypeParameters.clear();
      for (TypeParameter parameter in typeParameters) {
        if (seenTypeParameters.add(parameter)) {
          sb.clear();
          writeTypeParameter(parameter, sb);
          parameterStrings.add("$sb");
        }
      }
    }
    if (parameterStrings.isNotEmpty) {
      arguments.add(parameterStrings);
    }
    checks.add(<String, dynamic>{
      "kind": expected ? "isSubtype" : "isNotSubtype",
      "arguments": arguments,
    });
  }

  void writeTypeParameter(TypeParameter parameter, StringBuffer sb) {
    sb.write(computeName(parameter));
    if (parameter.defaultType is! DynamicType ||
        parameter.bound is DynamicType) {
      sb.write(" extends ");
      parameter.bound.accept1(this, sb);
    }
  }

  void writeTypeParameters(
      List<TypeParameter> typeParameters, StringBuffer sb) {
    if (typeParameters.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (TypeParameter p in typeParameters) {
        if (!first) sb.write(", ");
        writeTypeParameter(p, sb);
        first = false;
      }
      sb.write(">");
    }
  }

  void writeClasses() {
    Set<Class> writtenClasses = new Set<Class>();
    for (TreeNode node in nodeNames.keys.toList()) {
      if (node is Class) {
        writeClass(node, writtenClasses);
      }
    }
  }

  void writeClass(Class cls, Set<Class> writtenClasses) {
    if (cls == null || !writtenClasses.add(cls)) return;
    Supertype supertype = cls.supertype;
    writeClass(supertype?.classNode, writtenClasses);
    Supertype mixedInType = cls.mixedInType;
    writeClass(mixedInType?.classNode, writtenClasses);
    for (Supertype implementedType in cls.implementedTypes) {
      writeClass(implementedType.classNode, writtenClasses);
    }
    StringBuffer sb = new StringBuffer();
    sb.write("class ");
    sb.write(computeName(cls));
    writeTypeParameters(cls.typeParameters, sb);
    if (supertype != null) {
      sb.write(" extends ");
      supertype.asInterfaceType.accept1(this, sb);
    }
    if (mixedInType != null) {
      sb.write(" with ");
      mixedInType.asInterfaceType.accept1(this, sb);
    }
    bool first = true;
    for (Supertype implementedType in cls.implementedTypes) {
      if (first) {
        sb.write(" implements ");
      } else {
        sb.write(", ");
      }
      implementedType.asInterfaceType.accept1(this, sb);
      first = false;
    }
    Procedure callOperator;
    for (Procedure procedure in cls.procedures) {
      if (procedure.name.name == "call") {
        callOperator = procedure;
      }
    }
    if (callOperator != null) {
      sb.write("{ ");
      callOperator.function.functionType.accept1(this, sb);
      sb.write(" }");
    } else {
      sb.write(";");
    }
    classes.add("$sb");
  }

  String computeName(TreeNode node) {
    String name = nodeNames[node];
    if (name != null) return name;
    if (node is Class) {
      Library library = node.enclosingLibrary;
      if ("${library?.importUri}" == "dart:core") {
        if (!usedNames.add(node.name)) {
          throw "Class name conflict for $node";
        }
        return nodeNames[node] = node.name;
      }
    }
    while (!usedNames.add(name = names.current)) {
      names.moveNext();
    }
    names.moveNext();
    return nodeNames[node] = name;
  }

  @override
  void defaultDartType(DartType node, StringBuffer sb) {
    if (node is UnknownType) {
      sb.write("?");
    } else {
      throw "Unsupported: ${node.runtimeType}";
    }
  }

  @override
  void visitInvalidType(InvalidType node, StringBuffer sb) {
    throw "not implemented";
  }

  @override
  void visitDynamicType(DynamicType node, StringBuffer sb) {
    sb.write("dynamic");
  }

  @override
  void visitVoidType(VoidType node, StringBuffer sb) {
    sb.write("void");
  }

  @override
  void visitBottomType(BottomType node, StringBuffer sb) {
    sb.write("⊥");
  }

  @override
  void visitInterfaceType(InterfaceType node, StringBuffer sb) {
    sb.write(computeName(node.classNode));
    if (node.typeArguments.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (DartType type in node.typeArguments) {
        if (!first) sb.write(", ");
        type.accept1(this, sb);
        first = false;
      }
      sb.write(">");
    }
  }

  @override
  void visitFunctionType(FunctionType node, StringBuffer sb) {
    writeTypeParameters(node.typeParameters, sb);
    sb.write("(");
    bool first = true;
    for (int i = 0; i < node.requiredParameterCount; i++) {
      if (!first) sb.write(", ");
      node.positionalParameters[i].accept1(this, sb);
      first = false;
    }
    if (node.requiredParameterCount != node.positionalParameters.length) {
      if (!first) sb.write(", ");
      sb.write("[");
      first = true;
      for (int i = node.requiredParameterCount;
          i < node.positionalParameters.length;
          i++) {
        if (!first) sb.write(", ");
        node.positionalParameters[i].accept1(this, sb);
        first = false;
      }
      sb.write("]");
      first = false;
    }
    if (node.namedParameters.isNotEmpty) {
      if (!first) sb.write(", ");
      sb.write("{");
      first = true;
      for (NamedType named in node.namedParameters) {
        if (!first) sb.write(", ");
        named.type.accept1(this, sb);
        sb.write(" ");
        sb.write(named.name);
        first = false;
      }
      sb.write("}");
      first = false;
    }
    sb.write(") -> ");
    node.returnType.accept1(this, sb);
  }

  @override
  void visitTypeParameterType(TypeParameterType node, StringBuffer sb) {
    String name = computeName(node.parameter);
    usedTypeParameters.add(node.parameter);
    sb.write(name);
    if (node.promotedBound != null) {
      sb.write(" & ");
      node.promotedBound.accept1(this, sb);
    }
  }

  @override
  void visitTypedefType(TypedefType node, StringBuffer sb) {
    throw "not implemented";
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "classes": classes,
      "checks": checks,
    };
  }

  static writeTypeChecks(String filename, List<Object> typeChecks) {
    new File(filename)
        .writeAsString(new BenchMaker().serializeTypeChecks(typeChecks));
  }
}
