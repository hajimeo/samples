/*
 * Copyright (c) 2008, 2015, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the Classpath exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */



/*
 * This sample demonstrates simple preprocessor in BTrace.
 * When you run this sample against a Java process, you have
 * to specify -I . option so that the preprocessor can find
 * the "btracedefs.h" file:
 *
 *    btrace -I . <pid> ThreadBean.java
 *
 * Without -I option in command, BTrace skips preprocessor
 * invocation.
 */
#include"btracedefs.h"

        BTRACE_IMPORT

/**
 * This sample demonstrates that you can expose a BTrace
 * class as a JMX MBean. After connecting BTrace to the
 * target application, connect VisualVM or jconsole or 
 * any other JMX client to the same application.
 */
        BTRACE ThreadBean{

        // PROPERTY makes the count field to be exposed
        // as an attribute of this MBean.
        PROPERTY long count;

@OnMethod(
        clazz = "java.lang.Thread",
        method = "start"
)
    ACTION onnewThread(@Self Thread t){
        count++;
        }

@OnTimer(2000)
    ACTION ontimer(){
            println(count);
            }
            }
