// Reusable skeletal animation: named bones/sockets, pose blending and skinning transforms.
// Geometry and math come from MyMath; interned identifiers come from MyBasic.
// Asset loading, materials and game animation policy remain outside this module.
#scope_module
Basic :: #import "Basic";
Math :: #import "MyMath";
Names :: #import "MyBasic";
using Math;

#scope_export
#load "skeleton.jai";
